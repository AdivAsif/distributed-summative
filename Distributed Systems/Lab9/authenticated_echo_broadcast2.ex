defmodule AuthenticatedEchoBroadcast do
    def start(name, processes, sender, f) do
        pid = spawn(AuthenticatedEchoBroadcast, :init, [name, processes, sender, f])

        case :global.re_register_name(name, pid) do
            :yes -> pid
            :no  -> :error
        end
        IO.puts "registered #{name}"
        pid
    end

    # Init event must be the first
    # one after the component is created
    def init(name, processes, sender, f) do
        # Pause to allow all processes to register
        Process.sleep(100)
        state = %{
            name: name,
            processes: processes,
            sender: sender,
            f: f,

            sentecho: false,
            delivered: false,
            echos: %{},

        }
        run(state)
    end

    def run(state) do

        state = receive do
            {:broadcast, m} ->
                # Use beb_broadcast to broadcast {:send, state.name, m} to all processes
                beb_broadcast(:send, state.name, m)
                state

            {:send, sender, m} ->
                if state.sender == sender and not state.sentecho do
                    # Use beb_broadcast to broadcast {:echo, state.name, m} to all processes
                    beb_broadcast(:echo, state.name, m)
                    # Update sentecho to remember that echo has been sent
                    # %{state | sentecho: ...}
                    %{state | sentecho: true}
                else
                    state
                end

            {:echo, sender, m} ->
                # add the mapping sender -> m to state.echos
                # state = %{state | echos: ...}
                %{state | echos: }
                # An echo was received - schedule the internal event handler
                send(self(), {:internal_event})
                state

            {:internal_event} ->
                # Call the internal event handler
                check_internal_events(state)


            {:deliver, proc, m} ->
                # Message m is ready for delivery - print it out
                IO.puts("#{inspect state.name}: BCB-deliver: #{inspect m} from #{inspect proc}")
                state

        end
        run(state)
    end

    # Internal event handler: called whenever new echos are received
    def check_internal_events(state) do
            # Examine the content of state.echos
            # to determine if it includes a message m such that
            # the number processes mapped to m is a super-majority, i.e.,
            # > (length(state.processes) + state.f)/2
            # If so, trigger {:deliver, state.sender, m}, and set state.delivered to true;
            # else do nothing.
            # Do not forget to return the state in either case!
    end

    # Send message m point-to-point to process p
    defp unicast(m, p) do
        case :global.whereis_name(p) do
                pid when is_pid(pid) -> send(pid, m)
                :undefined -> :ok
        end
    end

    # Best-effort broadcast of m to the set of destinations dest
    defp beb_broadcast(m, dest), do: for p <- dest, do: unicast(m, p)

end
