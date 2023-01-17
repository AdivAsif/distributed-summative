defmodule Paxos do
  def start(name, participants) do
    pid = spawn(Paxos, :init, [name, participants])

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
      instances: %{},
      caller: nil
    }

    run(state)
  end

  def run(state) do
    state =
      receive do
        {:propose, inst, value, caller} ->
          beb({:set_caller, caller}, state.participants)

          state = %{
            state
            | instances: update_instance_state(state.instances, inst, :proposedValue, value)
          }

          ballot = create_ballot(state.instances[inst].maxBallot, state.participants)
          beb({:prepare, {0, state.name, inst}}, state.participants)

          state = %{
            state
            | instances: update_instance_state(state.instances, inst, :maxBallot, ballot)
          }

          state

        {:prepare, {ballot, sender, inst}} ->
          state = %{
            state
            | instances: update_instance_state(state.instances, inst, :maxBallot, ballot)
          }

          IO.puts("#{inspect(state.instances)} #{state.name}")
          IO.puts("#{inspect(state.instances[inst])}")

          if state.instances[inst].maxBallot > ballot &&
               Map.has_key?(state.instances[inst].prevVotes, state.instances[inst].maxBallot) do
            unicast(
              {:prepared, ballot,
               {state.instances[inst].maxBallot,
                Map.get(state.instances[inst].votes, state.instances[inst].maxBallot)}, inst},
              sender
            )
          else
            unicast({:prepared, ballot, {:none}, inst}, sender)
          end

          state

        {:prepared, ballot, vote, inst} ->
          state = %{
            state
            | instances:
                update_instance_state(
                  state.instances,
                  inst,
                  :preparePhase,
                  Map.put(state.instances[inst].preparePhase, ballot, [
                    vote | Map.get(state.instances[inst].preparePhase, ballot, [])
                  ])
                )
          }

          IO.puts("#{inspect state.instances[inst]}")
          if length(Map.get(state.instances[inst].preparePhase, ballot, [])) ==
               div(length(state.participants), 2) + 1 do
            if List.foldl(Map.get(state.instances[inst].preparePhase, ballot, []), true, fn elem,
                                                                                            acc ->
                 elem == {:none} && acc
               end) do
              beb(
                {:accept, state.instances[inst].maxBallot, state.instances[inst].proposedValue,
                 state.name, inst},
                state.participants
              )

              state = %{
                state
                | instances:
                    update_instance_state(
                      state.instances,
                      inst,
                      :votes,
                      Map.put(
                        state.instances[inst].votes,
                        state.instances[inst].maxBallot,
                        state.instances[inst].proposedValue
                      )
                    )
              }

              state
            else
              preparedList =
                delete_all_occurences(
                  Map.get(state.instances[inst].preparePhase, ballot, []),
                  {:none}
                )

              {maxBallot, maxBallotRes} =
                List.foldl(preparedList, {0, nil}, fn {ballotNumber, ballotRes},
                                                      {accBallotNumber, accBallotRes} ->
                  if ballotNumber > accBallotNumber do
                    {ballotNumber, ballotRes}
                  else
                    {accBallotNumber, accBallotRes}
                  end
                end)

              beb({:accept, maxBallot, maxBallotRes, state.name, inst}, state.participants)

              state = %{
                state
                | instances:
                    update_instance_state(state.instances, inst, :maxBallot, maxBallotRes)
              }

              state
            end
          else
            state
          end

        {:accept, ballot, result, sender, inst} ->
          if state.instances[inst].maxBallot <= ballot do
            state = %{
              state
              | instances:
                  update_instance_state(
                    state.instances,
                    inst,
                    :votes,
                    Map.put(state.instances[inst].votes, ballot, result)
                  )
            }

            unicast({:accepted, ballot, inst}, sender)
            state
          else
            state
          end

        {:accepted, ballot, inst} ->
          state = %{
            state
            | instances:
                update_instance_state(
                  state.instances,
                  inst,
                  :acceptPhase,
                  Map.put(state.instances[inst].acceptPhase, ballot, [
                    inst | Map.get(state.instances[inst].acceptPhase, ballot, [])
                  ])
                )
          }

          if length(Map.get(state.instances[inst].acceptPhase, ballot, [])) ==
               div(length(state.participants), 2) + 1 do
            beb(
              {:decided, inst, Map.get(state.instances[inst].votes, ballot)},
              state.participants
            )
          end

          state

        {:decided, inst, v} ->
          send(state.caller, {:decided, v})

          state = %{
            state
            | instances: update_instance_state(state.instances, inst, :decidedValue, v)
          }

          state

        {:get_decision, inst, caller} ->
          if state.instances[inst].decidedValue == nil do
            send(caller, nil)
          else
            send(caller, {:decided, state.instances[inst].decidedValue})
          end

          state

        {:set_caller, caller} ->
          state = %{state | caller: caller}
          state
      end

    run(state)
  end

  def propose(pid, inst, value, t) do
    send(pid, {:propose, inst, value, self()})

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
    send(pid, {:get_decision, inst, self()})

    receive do
      {:decided, v} ->
        v

      {nil} ->
        nil
    after
      t ->
        nil
    end
  end

  # helper methods
  defp create_ballot(ballot, participants), do: ballot + (length(participants) + 1)

  defp update_instance_state(instances, inst, key, value) do
    if Map.has_key?(instances, inst) do
      Map.put(instances[inst], key, value)
    else
      Map.put(instances, inst, %{
        proposedValue: nil,
        maxBallot: 0,
        preparePhase: %{},
        acceptPhase: %{},
        votes: %{},
        decidedValue: nil
      })
    end
  end

  defp delete_all_occurences(list, element), do: delete_all_occurences(list, element, [])

  defp delete_all_occurences([head | tail], element, list) when head === element,
    do: delete_all_occurences(tail, element, list)

  defp delete_all_occurences([head | tail], element, list),
    do: delete_all_occurences(tail, element, [head | list])

  defp delete_all_occurences([], _element, list), do: list

  # message sending helpers
  def beb(m, dest), do: for(p <- dest, do: unicast(m, p))

  defp unicast(m, p) do
    case :global.whereis_name(p) do
      pid when is_pid(pid) -> send(pid, m)
      :undefined -> :ok
    end
  end
end
