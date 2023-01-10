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
      maxBallotNumber: 0,
      prevVotes: %{},
      prepareResults: %{},
      acceptResults: %{},
      proposedValue: nil
    }

    run(state)
  end

  def run(state) do
    state =
      receive do
        {:propose, pid, inst, value, t} ->
          state = %{state | proposedValue: value}
          ballotNumber = generate_ballot_number(state.maxBallotNumber, state.participants)
          beb(state.participants, {:prepare, {0, state.name}})
          state = %{state | maxBallotNumber: ballotNumber}
          state

        {:prepare, {b, senderName}} ->
          if state.maxBallotNumber > b && Map.has_key?(state.prevVotes, state.maxBallotNumber) do
            send_msg(
              senderName,
              {:prepared, b,
               {state.maxBallotNumber, Map.get(state.prevVotes, state.maxBallotNumber)}}
            )
          else
            send_msg(senderName, {:prepared, b, {:none}})
          end

          state

        {:prepared, b, x} ->
          state = %{
            state
            | prepareResults:
                Map.put(state.prepareResults, b, [x | Map.get(state.prepareResults, b, [])])
          }

          if length(Map.get(state.prepareResults, b, [])) ==
               div(length(state.participants), 2) + 1 do
            if List.foldl(Map.get(state.prepareResults, b, []), true, fn elem, acc ->
                 elem == {:none} && acc
               end) do
              beb(
                state.participants,
                {:accept, state.maxBallotNumber, state.proposedValue, state.name}
              )

              state = %{
                state
                | prevVotes: Map.put(state.prevVotes, state.maxBallotNumber, state.proposedValue)
              }

              state
            else
              resultList = delete_all_occurences(Map.get(state.prepareResults, b, []), {:none})

              {maxBallotNumber, maxBallotRes} =
                List.foldl(resultList, {0, nil}, fn {ballotNumber, ballotRes},
                                                    {accBallotNumber, accBallotRes} ->
                  if ballotNumber > accBallotNumber do
                    {ballotNumber, ballotRes}
                  else
                    {accBallotNumber, accBallotRes}
                  end
                end)

              beb(state.participants, {:accept, maxBallotNumber, maxBallotRes, state.name})

              state = %{
                state
                | maxBallotNumber: maxBallotNumber,
                  prevVotes: Map.put(state.prevVotes, maxBallotNumber, maxBallotRes)
              }

              state
            end
          else
            state
          end

        {:accept, ballotNumber, result, sender} ->
          if state.maxBallotNumber <= ballotNumber do
            state = %{
              state
              | maxBallotNumber: ballotNumber,
                prevVotes: Map.put(state.prevVotes, ballotNumber, result)
            }

            send_msg(sender, {:accepted, ballotNumber})
            state
          else
            state
          end

        {:accepted, ballotNumber} ->
          state = %{
            state
            | acceptResults:
                Map.put(
                  state.acceptResults,
                  ballotNumber,
                  Map.get(state.acceptResults, ballotNumber, 0) + 1
                )
          }

          if Map.get(state.acceptResults, ballotNumber, 0) ==
               div(length(state.participants), 2) + 1 do
            beb(state.participants, {:decided, Map.get(state.prevVotes, ballotNumber)})
          end

          state

        {:decided, v} ->
          send(self, {:decision, v})
          state

        {:get_decision, pid, inst, t} ->
          if state.proposedValue == nil do
            IO.puts("#{inspect(state)}")
            nil
          else
            IO.puts("#{inspect(state.proposedValue)}")
            state.proposedValue
          end

          state

        {:print_state} ->
          IO.puts("#{inspect(state)}")
          state

        _ ->
          state
      end

    run(state)
  end

  def propose(pid, inst, value, t) do
    send(pid, {:propose, pid, inst, value, t})
  end

  def get_decision(pid, inst, t) do
    send(pid, {:get_decision, pid, inst, t})
  end

  defp generate_ballot_number(maxBallotNumber, participants) do
    maxBallotNumber + (length(participants) + 1)
  end

  defp beb(participants, msg) do
    for p <- participants do
      send_msg(p, msg)
    end
  end

  defp send_msg(name, msg) do
    case :global.whereis_name(name) do
      :undefined -> nil
      pid -> send(pid, msg)
    end
  end

  defp delete_all_occurences(list, element) do
    _delete_all_occurences(list, element, [])
  end

  defp _delete_all_occurences([head | tail], element, list) when head === element do
    _delete_all_occurences(tail, element, list)
  end

  defp _delete_all_occurences([head | tail], element, list) do
    _delete_all_occurences(tail, element, [head | list])
  end

  defp _delete_all_occurences([], _element, list) do
    list
  end
end
