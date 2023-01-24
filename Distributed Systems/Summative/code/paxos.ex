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
      instances: %{
        1 => %{
          proposedValue: nil,
          maxBallot: nil,
          preparePhase: %{},
          acceptPhase: %{},
          votes: %{},
          decidedValue: nil
        },
        2 => %{
          proposedValue: nil,
          maxBallot: nil,
          preparePhase: %{},
          acceptPhase: %{},
          votes: %{},
          decidedValue: nil
        }
      },
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
            | instances:
                Map.put(
                  state.instances,
                  inst,
                  Map.put(state.instances[inst], :proposedValue, value)
                )
          }

          ballotNumber =
            cond do
              state.instances[inst].maxBallot == nil -> create_ballot({0, state.name})
              true -> create_ballot(state.instances[inst].maxBallot)
            end

          beb({:prepare, {0, state.name}, state.name, inst}, state.participants)

          state = %{
            state
            | instances:
                Map.put(
                  state.instances,
                  inst,
                  Map.put(state.instances[inst], :maxBallot, ballotNumber)
                )
          }

          state

        {:prepare, ballot, sender, inst} ->
          if state.instances[inst].maxBallot > ballot &&
               Map.has_key?(state.instances[inst].votes, state.instances[inst].maxBallot) do
            unicast(
              {:promise, ballot,
               {state.instances[inst].maxBallot,
                Map.get(state.instances[inst].votes, state.instances[inst].maxBallot)}, inst},
              sender
            )
          else
            unicast({:promise, ballot, {:ack}, inst}, sender)
          end

          state

        {:promise, ballot, vote, inst} ->
          state = %{
            state
            | instances:
                Map.put(
                  state.instances,
                  inst,
                  Map.put(
                    state.instances[inst],
                    :preparePhase,
                    Map.put(state.instances[inst].preparePhase, ballot, [
                      vote | Map.get(state.instances[inst].preparePhase, ballot, [])
                    ])
                  )
                )
          }

          if length(Map.get(state.instances[inst].preparePhase, ballot, [])) ==
               div(length(state.participants), 2) + 1 do
            if Enum.all?(Map.get(state.instances[inst].preparePhase, ballot, []), fn x ->
                 x == {:ack}
               end) do
              beb(
                {:accept, state.instances[inst].maxBallot, state.instances[inst].proposedValue,
                 state.name, inst},
                state.participants
              )

              state = %{
                state
                | instances:
                    Map.put(
                      state.instances,
                      inst,
                      Map.put(
                        state.instances[inst],
                        :votes,
                        Map.put(
                          state.instances[inst].votes,
                          state.instances[inst].maxBallot,
                          state.instances[inst].proposedValue
                        )
                      )
                    )
              }

              state
            else
              promisedValues =
                Enum.filter(Map.get(state.instances[inst].preparePhase, ballot, []), fn v ->
                  v != {:ack}
                end)

              {maxBallotNumber, maxBallotRes} = Enum.max(promisedValues)
              beb({:accept, maxBallotNumber, maxBallotRes, state.name, inst}, state.participants)

              state = %{
                state
                | instances:
                    Map.put(
                      state.instances,
                      inst,
                      Map.put(state.instances[inst], :maxBallot, maxBallotNumber)
                    )
              }

              state = %{
                state
                | instances:
                    Map.put(
                      state.instances,
                      inst,
                      Map.put(
                        state.instances[inst],
                        :votes,
                        Map.put(state.instances[inst].votes, maxBallotNumber, maxBallotRes)
                      )
                    )
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
                  Map.put(
                    state.instances,
                    inst,
                    Map.put(
                      state.instances[inst],
                      :votes,
                      Map.put(state.instances[inst].votes, ballot, result)
                    )
                  )
            }

            state = %{
              state
              | instances:
                  Map.put(
                    state.instances,
                    inst,
                    Map.put(state.instances[inst], :maxBallot, ballot)
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
                Map.put(
                  state.instances,
                  inst,
                  Map.put(
                    state.instances[inst],
                    :acceptPhase,
                    Map.put(
                      state.instances[inst].acceptPhase,
                      ballot,
                      Map.get(state.instances[inst].acceptPhase, ballot, 0) + 1
                    )
                  )
                )
          }

          if Map.get(state.instances[inst].acceptPhase, ballot, 0) ==
               div(length(state.participants), 2) + 1 do
            beb(
              {:decided, inst, Map.get(state.instances[inst].votes, ballot)},
              state.participants
            )
          end

          state

        {:decided, inst, v} ->
          state = %{
            state
            | instances:
                Map.put(state.instances, inst, Map.put(state.instances[inst], :decidedValue, v))
          }

          send(state.caller, {:decided, state.instances[inst].decidedValue})
          state

        {:get_decision, inst, caller} ->
          if state.instances[inst].decidedValue == nil do
            send(caller, nil)
          else
            send(caller, {:final_decision, state.instances[inst].decidedValue})
          end

          state

        {:set_caller, caller} ->
          state =
            cond do
              state.caller == nil -> %{state | caller: caller}
              true -> state
            end

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
      {:final_decision, v} ->
        v

      {nil} ->
        nil
    after
      t ->
        nil
    end
  end

  # helper methods
  defp create_ballot({number, caller}), do: {number + 1, caller}

  # message sending helpers
  def beb(m, dest), do: for(p <- dest, do: unicast(m, p))

  defp unicast(m, p) do
    case :global.whereis_name(p) do
      pid when is_pid(pid) -> send(pid, m)
      :undefined -> :ok
    end
  end
end
