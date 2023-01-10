defmodule Paxos do
  def start(name, participants) do
    pid = spawn(Paxos, :init, [name, participants])
    # :global.unregister_name(name)

    case :global.re_register_name(name, pid) do
      :yes -> pid
      :no -> :error
    end

    IO.puts("registered #{name}")
    pid
  end

  def init(name, participants) do
    state = %{
      name: name,
      participants: participants,
      minBallotNumber: 0,
      prevVotes: %{},
      prepareResults: %{},
      acceptResults: %{},
      proposedValue: nil
    }

    run(state)
  end

  def run(state) do
    receive do
      {:propose, pid, inst, value, t} ->
        {new_state, decided_value} = {state, value}
        {:ok, new_state, decided_value}
    end

    run(state)
  end

  def propose(pid, inst, value, t) do
    send(pid, {:propose, pid, inst, value, t})

    receive do
      {:ok, new_state, decided_value} ->
        decided_value

      {:error, reason} ->
        {:error, reason}
    end
  end
end
