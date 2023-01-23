defmodule SeatReservation do
  def start(name, paxos_proc) do
    pid = spawn(SeatReservation, :init, [name, paxos_proc])

    pid =
      case :global.re_register_name(name, pid) do
        :yes -> pid
        :no -> nil
      end

    IO.puts(if pid, do: "registered #{name}", else: "failed to register #{name}")
    pid
  end

  def init(name, paxos_proc) do
    state = %{
      name: name,
      pax_pid: get_paxos_pid(paxos_proc),
      last_instance: 0,
      pending: {0, nil},
      seats: %{a1: :free, a2: :free, a3: :free, b1: :free, b2: :free, b3: :free}
    }

    run(state)
  end

  def run(state) do
    state =
      receive do
        {:seats, client} ->
          state = poll_for_decisions(state)
          send(client, {:seats, state.seats})
          state

        {:occupy, seat, client} = t ->
          state = poll_for_decisions(state)

          IO.puts("#{inspect Paxos.propose(state.pax_pid, state.last_instance + 1, t, 1000)}")
          if Paxos.propose(state.pax_pid, state.last_instance + 1, t, 1000) == {:abort} do
            send(client, {:abort})
          else
            %{state | pending: {state.last_instance + 1, client}}
          end

        {:poll_for_decisions} ->
          poll_for_decisions(state)

        _ ->
          state
      end

    run(state)
  end

  def get_seats(r) do
    send(r, {:seats, self()})

    receive do
      {:seats, seats} -> seats
    after
      10000 -> :timeout
    end
  end

  def occupy(r, seat) do
    send(r, {:occupy, seat, self()})

    case wait_for_reply(r, 5) do
      {:occupy_ok} -> :ok
      {:occupy_failed} -> :fail
      {:abort} -> :fail
      _ -> :timeout
    end
  end

  # helper methods
  defp get_paxos_pid(paxos_proc) do
    case :global.whereis_name(paxos_proc) do
      pid when is_pid(pid) -> pid
      :undefined -> raise(Atom.to_string(paxos_proc))
    end
  end

  defp wait_for_reply(_, 0), do: nil

  defp wait_for_reply(r, attempt) do
    msg =
      receive do
        msg -> msg
      after
        1000 ->
          send(r, {:poll_for_decisions})
          nil
      end

    if msg, do: msg, else: wait_for_reply(r, attempt - 1)
  end

  defp poll_for_decisions(state) do
    case Paxos.get_decision(state.pax_pid, i = state.last_instance + 1, 1000) do
      {:occupy, seat, client} ->
        state =
          case state.pending do
            {^i, ^client} ->
              send(elem(state.pending, 1), {:occupy_ok})
              %{state | pending: {0, nil}, seats: Map.put(state.seats, seat, :occupied)}

            {^i, _} ->
              send(elem(state.pending, 1), {:occupy_failed})
              %{state | pending: {0, nil}, seats: Map.put(state.seats, seat, :occupied)}

            _ ->
              %{state | seats: Map.put(state.seats, seat, :occupied)}
          end

        poll_for_decisions(%{state | last_instance: i})

      nil ->
        state
    end
  end
end
