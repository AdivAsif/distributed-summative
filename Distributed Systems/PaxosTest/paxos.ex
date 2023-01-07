defmodule Paxos do
  def start(name, nodes, upper_layer) do
    pid = spawn(Paxos, :init, [nodes, upper_layer, name])
    :global.unregister_name(name)

    case :global.register_name(name, pid) do
      :yes -> pid
      :no -> :error
    end

    pid
  end

  def init(nodes, upper_layer, name) do
    state = %{
      name: name,
      maxBallotNumber: 0,
      prevVotes: %{},
      prepareResults: %{},
      acceptResults: %{},
      nodes: nodes,
      upperLayer: upper_layer,
      proposedValue: nil
    }

    run(state)
  end

  def propose(pid, value) do
    send(pid, {:propose, value})
  end

  def start_ballot(pid) do
    send(pid, {:start_ballot})
  end

  defp generate_ballot_number(maxBallotNumber, nodes) do
    maxBallotNumber + (length(nodes) + 1)
  end

  defp beb(recipients, msg) do
    for r <- recipients do
      send_msg(r, msg)
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

  defp run(state) do
    state =
      receive do
        {:start_ballot} ->
          ballotNumber = generate_ballot_number(state.maxBallotNumber, state.nodes)
          beb(state.nodes, {:prepare, {0, state.name}})
          state = %{state | maxBallotNumber: ballotNumber}
          state

        {:prepare, {b, senderName}} ->
          if state.maxBallotNumber > b && Map.has_key?(state.prevVotes, state.maxBallotNumber) do
            send_msg(
              senderName,
              {
                :prepared,
                b,
                {state.maxBallotNumber, Map.get(state.prevVotes, state.maxBallotNumber)}
              }
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
               div(length(state.nodes), 2) + 1 do
            if List.foldl(Map.get(state.prepareResults, b, []), true, fn elem, acc ->
                 elem == {:none} && acc
               end) do
              beb(
                state.nodes,
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

              beb(state.nodes, {:accept, maxBallotNumber, maxBallotRes, state.name})

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
          # Check quorum of accepted received

          state = %{
            state
            | acceptResults:
                Map.put(
                  state.acceptResults,
                  ballotNumber,
                  Map.get(state.acceptResults, ballotNumber, 0) + 1
                )
          }

          if(
            Map.get(state.acceptResults, ballotNumber, 0) ==
              div(length(state.nodes), 2) + 1
          ) do
            beb(state.nodes, {:decided, Map.get(state.prevVotes, ballotNumber)})
          end

          state

        {:decided, v} ->
          send(state.upperLayer, {:decide, v})
          state

        {:propose, value} ->
          %{state | proposedValue: value}

        _ ->
          state
      end

    run(state)
  end
end
