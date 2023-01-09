defmodule Paxos do
  def start(name, participants) do
    pid = spawn(Paxos, :init, [name, participants])
    :global.unregister_name(name)

    case :global.re_register_name(name, pid) do
      :yes -> pid
      :no -> :error
    end

    IO.puts("Registered #{name}")
    pid
  end

  def init(name, participants) do
    state = %{
      name: name,
      participants: participants,
      minBallotNumber: %{},
      prevVotes: %{},
      prepareValues: %{},
      acceptValues: %{},
      proposedValue: %{}
    }

    run(state)
  end

  def run(state) do
    state =
      receive do
        {:propose, pid, inst, value, t} ->
          state = %{state | proposedValue: Map.put(state.proposedValue, inst, value)}
          ballotNumber = get_ballot_number(inst, state.minBallotNumber, state.participants)
          beb(state.participants, {:prepare, {b, i, sender}})
          state = %{state | minBallotNumber: Map.put(state.minBallotNumber, inst, ballotNumber)}
          state

        {:prepare, {b, i, sender}} ->
          if Map.get(state.minBallotNumber, i, 0) > b &&
               Map.has_key?(state.prevVotes, Map.get(state.minBallotNumber, i, 0)) do
            send_msg(
              sender,
              {:prepared, b, i,
               {state.minBallotNumber,
                Map.get(state.prevVotes, Map.get(state.minBallotNumber, inst))}}
            )
          else
            send_msg(sender, {:prepared, b, i, {:none}})
          end

          state

        {:prepared, b, i, prevVote} ->
          state = %{
            state
            | prepareResults:
                Map.put(state.prepareResults, b, [prevVote | Map.get(state.prepareResults, b, [])])
          }

          if length(Map.get(state.prepareResults, b, [])) ==
               div(length(state.participants), 2) + 1 do
            if(List.foldl(Map.get(state.prepareResults, b, []), true, fn elem, acc -> elem == {:none} && acc end))
          end do
            beb(state.participants, {:accept, state.minBallotNumber, state.proposedValue, state.name, i})
            state = %{state | prevVotes: Map.put(state.prevVotes, Map.get(state.minBallotNumber, i))}
          end
      end
  end

  defp beb(participants, msg) do
    for p <- participants do
      send_msg(p, msg)
    end
  end

  defp send_msg(proc, msg) do
    case :global.whereis_name(proc) do
      :undefined -> nil
      pid -> send(pid, msg)
    end
  end

  defp get_ballot_number(inst, minBallotNumber, participants) do
    if Map.has_key?(minBallotNumber, inst) do
      Map.get(minBallotNumber, inst)
    else
      length(participants) + 1
    end
  end
end
