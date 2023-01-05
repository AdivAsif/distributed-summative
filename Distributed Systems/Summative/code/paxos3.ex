defmodule Paxos do
  @delta 1000

  def start(name, participants) do
    pid = spawn(Paxos, :init, [name, participants])
    :global.unregister_name(name)

    case :global.re_register_name(name, pid) do
      :yes -> pid
      :no -> :error
    end
    IO.puts("registered #{name}")

    pid
  end

  def init(name, participants) do
    start_beb(name)
    state = %{
      name: name,
      participants: participants,
      alive: MapSet.new(participants),
      detected: %MapSet{},
      leader: nil,
      received: %MapSet{},
      proposals: %MapSet{},
      decisions: %MapSet{},
      ballots: %MapSet{},
      values: %MapSet{}
    }
    Process.send_after(self(), {:heartbeat}, @delta)
    run(state)
  end

  def run(state) do
    # IO.puts("#{inspect state} #{inspect {state.name, self()}}")
    state =
      receive do
        {:propose, pid, inst, value, t} ->
          handle_propose(state, pid, inst, value, t)
          state

        {:get_decision, pid, inst, t} ->
          handle_get_decision(state, pid, inst, t)
          state

        {:heartbeat} ->
          IO.puts("#{state.name}: #{inspect({:timeout})}")
          state = check_and_probe(state, state.participants)
          # state = %{state | alive: %MapSet{}}
          Process.send_after(self(), {:heartbeat}, @delta)
          state

        {:heartbeat_request, pid} ->
          IO.puts("#{state.name}: #{inspect({:heartbeat_request, pid})}")
          send(pid, {:heartbeat_reply, state.name})
          state

        {:heartbeat_reply, name} ->
          IO.puts("#{state.name}: #{inspect {:heartbeat_reply, name}}")
          IO.puts("#{inspect state}")
          %{state | alive: MapSet.put(state.alive, name)}
          state

        {:decision, inst, value} ->
          state = MapSet.put(state.decisions, {inst, value})
          state

        {:print_state} ->
          IO.puts("#{inspect(state)}")
          state
      end

    run(state)
  end

  def propose(pid, inst, value, t) do
    data_msg = {:propose, pid, inst, value, t}
    send(pid, data_msg)

    # receive do
    # after
    #   t -> {:timeout}
    # end
  end

  def get_decision(pid, inst, t) do
    data_msg = {:get_decision, pid, inst, t}
    send(pid, data_msg)

    # receive do
    # after
    #   t -> {:timeout}
    # end
  end

  defp handle_propose(state, pid, inst, value, t) do
    # Set the initial ballot number for this instance
    ballot = {state.name, 0}

    # Send a prepare message to all participants
    for participant <- state.participants do
      send(participant, {:prepare, inst, ballot})
    end

    # Set a timer for the timeout
    # timer = Process.send_after(self(), :timeout, t)

    # Receive responses from participants
    responses = MapSet.new()
    num_responses = 0

    receive do
      {:prepare, inst, ballot} ->
        IO.puts("Prepare: #{inspect(inst)} Ballot: #{inspect(ballot)} Value: #{inspect(value)}")
        # Check if the instance has already been decided
        if Map.has_key?(state.decisions, inst) do
          # Return the decided value if the instance has already been decided
          {:decision, Map.fetch(state.decisions, inst)}
          state
        else
          # Check if the ballot number is higher than the previous one
          prev_ballot = Map.fetch(state.ballots, inst)

          if ballot > prev_ballot do
            # Update the ballot number and value for the instance if the ballot number is higher
            state = %{state | ballots: MapSet.put(state.ballots, {inst, ballot})}
            IO.puts("Prepare Ballots: #{inspect(state.ballots)}")
            state = %{state | values: MapSet.put(state.values, {inst, value})}
            IO.puts("Prepare Values: #{inspect(state.values)}")
            # Send a promise message to the proposer
            send(pid, {:promise, inst, ballot, value})
            # Continue waiting for responses
            handle_propose(state, pid, inst, value, t)
            state
          else
            # Send a promise message to the proposer with the previous ballot number and value
            send(pid, {:promise, inst, prev_ballot, Map.fetch(state.values, inst)})
            # Continue waiting for responses
            handle_propose(state, pid, inst, value, t)
            state
          end
        end

      {:promise, inst, prev_ballot, prev_value} ->
        IO.puts(
          "Promise: #{inspect(inst)} Previous Ballot: #{inspect(prev_ballot)} Previous Value: #{inspect(prev_value)}"
        )

        if prev_ballot < ballot do
          # Update the ballot number if necessary
          ballot = {state.name, elem(prev_ballot, 1) + 1}
          # Update the state map with the new ballot number
          state = Map.put(state, :ballots, Map.put(state.ballots, inst, ballot))
          state
        end

        # Add the response to the set of responses
        responses = MapSet.put(responses, prev_value)
        num_responses = num_responses + 1
        # Check if a majority of responses have been received
        if num_responses > length(state.participants) / 2 do
          # Determine the value to propose based on the responses
          value = get_majority_value(responses)
          # Send an accept message to all participants
          for participant <- state.participants do
            send(participant, {:accept, inst, ballot, value})
          end

          # Receive acceptances from participants
          acceptances = MapSet.new()
          num_acceptances = 0

          receive do
            {:accept, inst, ballot, value} ->
              # Add the acceptance to the set of acceptances
              acceptances = MapSet.put(acceptances, value)
              num_acceptances = num_acceptances + 1
              state

            # Add a case for handling :accepted messages
            {:accepted, inst, ballot, value} ->
              # Add the acceptance to the set of acceptances
              acceptances = MapSet.put(acceptances, value)
              num_acceptances = num_acceptances + 1
              state
              # Add other cases for handling other messages here
          end

          # Check if a majority of acceptances have been received
          if num_acceptances > length(state.participants) / 2 do
            # Update the decision for the instance
            state = Map.put(state, :decisions, Map.put(state.decisions, inst, value))
            # Return the decided value
            {:decision, value}
            state
          else
            # Return abort if a majority of acceptances have not been received
            {:abort}
            state
          end
        else
          # Return abort if a majority of responses have not been received
          {:abort}
          state
        end

      # Add other cases
      {:accepted, inst, ballot, value} ->
        responses = MapSet.put(responses, value)
        num_responses = num_responses + 1
        state

        # :timeout ->
        #   # Return timeout if the timer expires
        #   Process.cancel_timer(timer)
        #   {:timeout}
        #   state
    end
  end

  defp handle_get_decision(state, pid, inst, t) do
    timer = Process.send_after(self(), :timeout, t)

    case Map.fetch!(state.decisions, inst) do
      {:decision, value} ->
        value
        state

      _ ->
        receive do
          {:decision, inst, value} ->
            state = %{state | decisions: MapSet.put(state.decisions, {inst, value})}
            value
            state

          :timeout ->
            {:timeout}
            state
        end

        state
    end
  end

  # Helper methods
  defp check_and_probe(state, []) do
    if MapSet.size(state.alive) > length(state.participants) / 2 do
      leader = get_leader(state.alive)
      if leader == state.name do
        state = %{state | leader: leader}
        state
      end
    end
  end
  defp check_and_probe(state, [p | p_tail]) do
    state = if p not in state.alive and p not in state.detected do
      state = %{state | detected: MapSet.put(state.detected, p)}
      state
    else
      state
    end
    case :global.whereis_name(p) do
      pid when is_pid(pid) -> send(pid, {:heartbeat_request, self()})
      :undefined -> :ok
    end

    check_and_probe(state, p_tail)
  end

  defp heartbeat(state) do
    # Send a heartbeat request to all participants
    # IO.puts("#{inspect Enum.map(state.participants, fn(p) -> :global.whereis_name(p) end)}")
    # beb_broadcast(:heartbeat, Enum.map(state.participants, fn(p) -> :global.whereis_name(p) end)})
    # IO.puts("#{inspect state.participants}")
    # IO.puts("#{inspect Enum.map(state.participants, fn(p) -> :global.whereis_name(p) end)}")
    for participant <- Enum.map(state.participants, fn(p) -> :global.whereis_name(p) end) do
      # pid = Process.whereis(participant)
      # IO.puts("#{inspect pid}")
      send(participant, :heartbeat)
    end

    # Receive heartbeat responses from participants
    receive do
      # Add a case for handling heartbeat responses
      :heartbeat ->
        # Add the responding process to the set of alive processes
        state = %{state | alive: MapSet.put(state.alive, self())}
        state
    after
      @delta ->
        # No response was received within the interval, so the process is considered not alive
        state = %{state | alive: MapSet.delete(state.alive, self())}
        state
    end

    # Check if a majority of processes are alive
    if MapSet.size(state.alive) > length(state.participants) / 2 do
      # Determine the leader
      leader = get_leader(state.alive)
      # Only the leader can propose values
      if leader == state.name do
        # Run Paxos as the leader
        state = %{state | leader: leader}
        state
      end
    else
      # A majority of processes are not alive, so restart the heartbeat process
      heartbeat(state)
    end
  end

  defp get_majority_value(responses) do
    # Create a map of value counts
    counts =
      Enum.reduce(responses, %{}, fn value, acc -> Map.update(acc, value, 1, &(&1 + 1)) end)

    # Get the maximum value count
    max_count = Map.values(counts) |> Enum.max()
    # Get the values with the maximum count
    majority_values =
      Map.keys(counts) |> Enum.filter(fn value -> Map.fetch(counts, value) == max_count end)

    # Return the first value in the list of majority values
    IO.puts("Majority value: #{inspect(Enum.at(majority_values, 0))}")
    Enum.at(majority_values, 0)
  end

  defp get_leader(alive) do
    sorted_alive = Enum.sort(alive, &(&1 > &2))
    hd(sorted_alive)
  end

  # Best Effort Broadcast helpers
  defp get_beb_name() do
    {:registered_name, parent} = Process.info(self(), :registered_name)
    String.to_atom(Atom.to_string(parent) <> "_beb")
  end

  defp start_beb(name) do
    Process.register(self(), name)
    pid = spawn(BestEffortBroadcast, :init, [])
    Process.register(pid, get_beb_name())
    Process.link(pid)
  end

  defp beb_broadcast(m, dest) do
    BestEffortBroadcast.beb_broadcast(Process.whereis(get_beb_name()), m, dest)
  end
end
