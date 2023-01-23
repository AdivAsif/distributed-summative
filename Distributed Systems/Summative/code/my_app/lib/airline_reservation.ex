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
      seats: %{a1: :free, a2: :free, a3: :free, b1: :free, b2: :free, b3: :free}
    }

    run(state)
  end

  def run(state) do
    state =
      receive do
        {:seats, client} ->
          IO.puts("Testing state of seats: #{inspect state.seats}")
          send(client, state.seats)
          state

        {:occupy, seat, client} ->
          if Map.has_key?(state.seats, seat) do
            Paxos.propose(state.pax_pid, state.last_instance + 1, seat, 1000)
            send(
              self(),
              {:decided, Paxos.get_decision(state.pax_pid, state.last_instance + 1, 1000)}
            )

            state
          else
            send(client, {:error, seat})
            state
          end

        {:decided, seat} ->
          if Map.get(state.seats, seat) == :free do
            state = %{state | seats: Map.put(state.seats, seat, :occupied)}
            state
          else
            :error
            state
          end
      end

    run(state)
  end

  def get_seats(r) do
    send(r, {:seats, self()})
  end

  def occupy(r, seat) do
    send(r, {:occupy, seat, self()})
  end

  # helper methods
  defp get_paxos_pid(paxos_proc) do
    case :global.whereis_name(paxos_proc) do
      pid when is_pid(pid) -> pid
      :undefined -> raise(Atom.to_string(paxos_proc))
    end
  end
end
