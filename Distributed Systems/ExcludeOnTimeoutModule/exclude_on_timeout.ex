defmodule ExcludeOnTimeout do

    def start(name, processes) do
        pid = spawn(ExcludeOnTimeout, :init, [name, processes])
        # :global.unregister_name(name)
        case :global.re_register_name(name, pid) do
            :yes -> pid
            :no  -> :error
        end
        IO.puts "registered #{name}"
        pid
    end

    # Init event must be the first
    # one after the component is created
    def init(name, processes) do
        state = %{
            name: name,
            processes: List.delete(processes, name),
            delta: 1000, # timeout in millis
            alive: MapSet.new(processes),
            detected: %MapSet{}
        }
        Process.send_after(self(), {:timeout}, state.delta)
        run(state)
    end

    def run(state) do
        state = receive do
            {:timeout} ->
                IO.puts("#{state.name}: #{inspect({:timeout})}")
                state = check_and_probe(state, state.processes)
                state = %{state | alive: %MapSet{}}
                Process.send_after(self(), {:timeout}, state.delta)
                state

            {:heartbeat_request, pid} ->
                IO.puts("#{state.name}: #{inspect({:heartbeat_request, pid})}")

                # Uncomment this line to simulate a delayed response by process :p1
                # This results in all processes detecting :p1 as crashed.
                # if state.name == :p1, do: Process.sleep(10000)

                send(pid, {:heartbeat_reply, state.name})
                state

            {:heartbeat_reply, name} ->
                IO.puts("#{state.name}: #{inspect {:heartbeat_reply, name}}")
                %{state | alive: MapSet.put(state.alive, name)}

            {:crash, p} ->
                IO.puts("#{state.name}: CRASH detected #{p}")
                state
        end
        run(state)
    end

    defp check_and_probe(state, []), do: state
    defp check_and_probe(state, [p | p_tail]) do
        state = if p not in state.alive and p not in state.detected do
            state = %{state | detected: MapSet.put(state.detected, p)}
            send(self(), {:crash, p})
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
end
