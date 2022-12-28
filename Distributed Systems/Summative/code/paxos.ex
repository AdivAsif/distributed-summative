defmodule Paxos do
  def start(name, participants) do
    pid = spawn(Paxos, :init, [name, participants])
    case :global.re_register_name(name, pid) do
      :yes -> pid
      :no -> :error
    end
    IO.puts "registered #{name}"
    pid
  end

  def init(name, participants) do
    start_beb(name)
    state = %{
      name: name,
      participants: participants,
      received: %MapSet{},
      proposals: %MapSet{},
      decisions: %MapSet{},
      ballots: %MapSet{},
      values: %MapSet{}
    }
    run(state)
  end

  def run(state) do
    IO.puts("#{inspect state} #{inspect {state.name, self()}}")
    state = receive do
      {:propose, pid, inst, value, t} ->
        handle_propose(state, pid, inst, value, t)
        state
      {:get_decision, pid, inst, t} ->
        handle_get_decision(state, pid, inst, t)
        state
      {:prepare, inst, ballot} ->
        IO.puts("#{inspect inst}")
      {:decision, inst, value} ->
        state = MapSet.put(state.decisions, {inst, value})
        state
    end
    run(state)
  end

  def propose(pid, inst, value, t) do
    data_msg = {:propose, pid, inst, value, t}
    send(pid, data_msg)
    receive do
      after t -> {:timeout}
    end
  end

  def get_decision(pid, inst, t) do
    data_msg = {:get_decision, pid, inst, t}
    send(self(), data_msg)
    receive do
      after t -> {:timeout}
    end
  end

  defp handle_propose(state, pid, inst, value, t) do
    # Set the initial ballot number for this instance
    ballot = {state.name, 0}
    IO.puts("#{inspect ballot}")
    # Send a prepare message to all participants
    for participant <- state.participants do
      send(participant, {:prepare, inst, ballot})
    end

    # Set a timer for the timeout
    timer = Process.send_after(self(), :timeout, t)

    # Receive responses from participants
    responses = MapSet.new
    num_responses = 0
    receive do
      {:prepare, inst, ballot} ->
        # Check if the instance has already been decided
        if Map.has_key?(state.decisions, inst) do
          # Return the decided value if the instance has already been decided
          {:decision, Map.fetch(state.decisions, inst)}
        else
          # Check if the ballot number is higher than the previous one
          prev_ballot = Map.fetch(state.ballots, inst)
          if ballot > prev_ballot do
            # Update the ballot number and value for the instance if the ballot number is higher
            state = Map.put(state, :ballots, Map.put(state.ballots, inst, ballot))
            state = Map.put(state, :values, Map.put(state.values, inst, value))
            # Send a promise message to the proposer
            send(pid, {:promise, inst, ballot, value})
            # Continue waiting for responses
            handle_propose(state, pid, inst, value, t)
          else
            # Send a promise message to the proposer with the previous ballot number and value
            send(pid, {:promise, inst, prev_ballot, Map.fetch(state.values, inst)})
            # Continue waiting for responses
            handle_propose(state, pid, inst, value, t)
          end
        end
      {:promise, inst, prev_ballot, prev_value} ->
        IO.puts("#{inspect inst}")
        if prev_ballot < ballot do
          # Update the ballot number if necessary
          ballot = {state.name, prev_ballot.value + 1}
          # Add the response to the set of responses
          responses = MapSet.put(responses, prev_value)
          num_responses = num_responses + 1
        else
          # Abort the proposal if a higher ballot has already been seen
          {:abort}
        end
        if num_responses < length(state.participants) do
          # Continue receiving responses if not all participants have responded
          handle_propose(state, pid, inst, value, t)
        else
          # Find the value with the most votes, or use the value being proposed if there are no votes
          value =
            if MapSet.size(responses) == 0 do
              value
            else
              Enum.max_by(responses, &(&1.votes))
            end

          # Send an accept message to all participants
          for participant <- state.participants do
            send(participant, {:accept, inst, ballot, value})
          end

          # Receive responses from participants
          num_accepts = 0
          receive do
            {:accepted, inst, _ballot} ->
              num_accepts = num_accepts + 1
              if num_accepts < length(state.participants) do
                # Continue receiving responses if not all participants have accepted
                handle_propose(state, pid, inst, value, t)
              else
                # Return the decided value
                {:decision, value}
              end
            :timeout ->
              # Return timeout if the timer expires
              {:timeout}
          end
        end
      :timeout ->
        # Return timeout if the timer expires
        {:timeout}
    end
  end

  defp handle_get_decision(state, pid, inst, t) do
    timer = Process.send_after(self(), :timeout, t)

    case Map.fetch!(state.decisions, inst) do
      {:decision, value} ->
        value
      _ ->
        receive do
          {:decision, inst, value} ->
            state = MapSet.put(state.decisions, {inst, value})
            value
          :timeout ->
            {:timeout}
        end
    end
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
