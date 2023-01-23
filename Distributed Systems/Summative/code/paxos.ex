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
      maxBallotNumber: nil,
      prevVotes: %{},
      prepareResults: %{},
      acceptResults: %{},
      proposedValue: nil,
      decidedValue: nil,
      caller: nil
    }

    run(state)
  end

  def run(state) do
    state =
      receive do
        {:propose, pid, inst, value, t, caller} ->
          beb(state.participants, {:set_caller, caller})
          state = %{state | proposedValue: value}

          # ballotNumber = generate_ballot_number(state.maxBallotNumber, state.participants)
          ballotNumber =
            cond do
              state.maxBallotNumber == nil -> create_ballot({0, state.name})
              true -> create_ballot(state.maxBallotNumber)
            end

          beb(state.participants, {:prepare, {0, state.name}, state.name})
          state = %{state | maxBallotNumber: ballotNumber}

          state

        {:prepare, b, senderName} ->
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

          IO.puts("Promise phase new state: #{inspect state}")

          if length(Map.get(state.prepareResults, b, [])) ==
               div(length(state.participants), 2) + 1 do
            if Enum.all?(Map.get(state.prepareResults, b, []), fn elem ->
                 elem == {:none}
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
              resultList =
                Enum.filter(Map.get(state.prepareResults, b, []), fn v -> v != {:none} end)

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
          state = %{state | decidedValue: v}
          send(state.caller, {:decision, v})
          state

        {:get_decision, pid, inst, t, caller} ->
          if state.decidedValue == nil do
            send(caller, nil)
          else
            send(caller, {:decided, state.decidedValue})
          end

          state

        {:set_caller, caller} ->
          state =
            cond do
              state.caller == nil -> %{state | caller: caller}
              true -> state
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
    send(pid, {:propose, pid, inst, value, t, self()})

    receive do
      {:decision, v} ->
        {:decision, v}

      {:abort} ->
        {:abort}
    after
      t ->
        {:timeout}
    end
  end

  def get_decision(pid, inst, t) do
    send(pid, {:get_decision, pid, inst, t, self()})

    receive do
      {:decided, v} ->
        v

      nil ->
        nil
    after
      t ->
        nil
    end
  end

  defp create_ballot({number, caller}), do: {number + 1, caller}

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
end
