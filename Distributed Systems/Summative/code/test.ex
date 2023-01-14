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
      minBallotNumber: %{},
      prevVotes: %{},
      prepareResults: %{},
      acceptResults: %{},
      proposedValue: %{}
    }

    run(state)
  end

  def run(state) do
    receive do
      {:propose, pid, inst, value, t, caller} ->
        {new_state, decided_value} = {state, value}
        IO.puts("#{inspect(decided_value)}")
        IO.puts("#{inspect caller}")
        send(caller, {:ok, decided_value})
        {:ok, new_state, decided_value}
    end

    run(state)
  end

  def propose(pid, inst, value, t) do
    send(pid, {:propose, pid, inst, value, t, self()})

    receive do
      {:ok, decide} ->
        IO.puts("#{inspect(decide)}")
        {:decision, decide}
    end
  end
end
