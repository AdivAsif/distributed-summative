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
    IO.puts("#{inspect state.instances} from process #{state.name}")
    state =
      receive do
        {:propose, pid, inst, value, t, caller} ->
          beb(state.participants, {:set_caller, caller})

          state = %{
            state
            | instances: update_instance(state.instances, inst, :proposedValue, value)
          }

          IO.puts("#{inspect state}")

          ballotNumber =
            generate_ballot_number(state.instances[inst].maxBallotNumber, state.participants)

          beb(state.participants, {:prepare, {0, state.name, inst}})

          state = %{
            state
            | instances: update_instance(state.instances, inst, :maxBallotNumber, ballotNumber)
          }

          state

        {:prepare, {b, senderName, inst}} ->
          if Map.has_key?(state.instances, inst) do
            if state.instances[inst].maxBallotNumber > b &&
                 Map.has_key?(
                   state.instances[inst].prevVotes,
                   state.instances[inst].maxBallotNumber
                 ) do
              send_msg(
                senderName,
                {:prepared, b,
                 {state.instances[inst].maxBallotNumber,
                  Map.get(state.instances[inst].prevVotes, state.instances[inst].maxBallotNumber)},
                 inst}
              )
            end
          else
            send_msg(senderName, {:prepared, b, {:none}, inst})
          end

          state

        {:prepared, b, x, inst} ->
          state = %{
            state
            | instances:
                update_instance(
                  state.instances,
                  inst,
                  :prepareResults,
                  Map.put(state.instances[inst].prepareResults, b, [
                    x | Map.get(state.instances[inst].prepareResults, b, [])
                  ])
                )
          }

          if length(Map.get(state.instances[inst].prepareResults, b, [])) ==
               div(length(state.participants), 2) + 1 do
            if List.foldl(Map.get(state.instances[inst].prepareResults, b, []), true, fn elem,
                                                                                         acc ->
                 elem == {:none} && acc
               end) do
              beb(
                state.participants,
                {:accept, state.instances[inst].maxBallotNumber,
                 state.instances[inst].proposedValue, state.name, inst}
              )

              state = %{
                state
                | instances:
                    update_instance(
                      state.instances,
                      inst,
                      :prevVotes,
                      Map.put(
                        state.instances[inst].prevVotes,
                        state.instances[inst].maxBallotNumber,
                        state.instances[inst].proposedValue
                      )
                    )
              }

              state
            else
              resultList =
                delete_all_occurences(
                  Map.get(state.instances[inst].prepareResults, b, []),
                  {:none}
                )

              {maxBallotNumber, maxBallotRes} =
                List.foldl(resultList, {0, nil}, fn {ballotNumber, ballotRes},
                                                    {accBallotNumber, accBallotRes} ->
                  if ballotNumber > accBallotNumber do
                    {ballotNumber, ballotRes}
                  else
                    {accBallotNumber, accBallotRes}
                  end
                end)

              beb(state.participants, {:accept, maxBallotNumber, maxBallotRes, state.name, inst})

              state = %{
                state
                | instances: update_instance(state.instances, inst, maxBallotNumber, maxBallotRes)
              }

              state
            end
          else
            state
          end

        {:accept, ballotNumber, result, sender, inst} ->
          if state.instances[inst].maxBallotNumber <= ballotNumber do
            state = %{
              state
              | instances:
                  update_instance(
                    state.instances,
                    inst,
                    :prevVotes,
                    Map.put(state.instances[inst].prevVotes, ballotNumber, result)
                  )
            }

            send_msg(sender, {:accepted, ballotNumber, inst})
            state
          else
            state
          end

        {:accepted, ballotNumber, inst} ->
          state = %{
            state
            | instances:
                update_instance(
                  state.instances,
                  inst,
                  :decided_value,
                  Map.put(state.instances[inst].acceptResults, ballotNumber, [
                    inst | Map.get(state.instances[inst].acceptResults, ballotNumber, [])
                  ])
                )
          }

          if length(Map.get(state.instances[inst].acceptResults, ballotNumber, [])) ==
               div(length(state.participants), 2) + 1 do
            state = %{
              state
              | instances: update_instance(state.instances, inst, :decided, true)
            }

            send(state.caller, {:decided, state.instances[inst].proposedValue, inst})
            state
          else
            state
          end

        {:get_decision, pid, inst, t, caller} ->
          if state.instances[inst].decided do
            send(caller, {:decided, state.instances[inst].decided_value})
            state
          else
            send(caller, nil)
            state
          end

        {:set_caller, caller} ->
          state = %{state | caller: caller}
          state

        {:print_state} ->
          IO.puts("#{inspect(state)}")
          state
      end

    run(state)
  end

  def update_instance(instances, inst, field, value) do
    IO.puts("Instances map: #{inspect instances} #{inspect {inst, field, value}}")
    if Map.has_key?(instances, inst) do
      IO.puts("test")
      Map.put(instances[inst], field, value)
    else
      Map.put(instances, inst, %{
        maxBallotNumber: 0,
        prevVotes: %{},
        prepareResults: %{},
        acceptResults: %{},
        proposedValue: nil,
        decided: false,
        decided_value: nil
      })
    end
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

  def generate_ballot_number(max_number, participants) do
    max_number + (length(participants) + 1)
  end

  def beb(recipients, msg) do
    for r <- recipients do
      send_msg(r, msg)
    end
  end

  def send_msg(name, msg) do
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
