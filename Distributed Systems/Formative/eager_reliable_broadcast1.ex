defmodule EagerReliableBroadcast do
    def start(name, processes) do
        pid = spawn(EagerReliableBroadcast, :init, [name, processes])
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
            processes: processes,

            # Tracks the sets of message sequence numbers received from each process
            delivered: (for p <- processes, into: %{}, do: {p, %MapSet{}}),

            # Tracks the highest contiguous message sequence number received from each process
            all_up_to: (for p <- processes, into: %{}, do: {p, -1}),

            # Current sequence number to assign to a newly broadcast message
            seq_no: 0
        }
        run(state)
    end

    def run(state) do
        state = receive do
            {:broadcast, m} ->
                data_msg = {:data, state.name, state.seq_no, m}
                state = %{state | seq_no: state.seq_no + 1}
                beb_broadcast(data_msg, state.processes)

                # Replace beb_broadcast above with the one below to
                # simulate the scenario in which :p0 does not broadcast to :p0 and :p1, and
                # no one broadcasts to :p0.
                # beb_broadcast_with_failures(state.name, :p0, [:p0, :p1], data_msg, state.processes)

                IO.puts("#{inspect state.name}: RB-broadcast: #{inspect m}")
                state

            {:data, proc, seq_no, m} ->
                # IO.puts("#{inspect state.name}: BEB-deliver: #{inspect m} from #{inspect proc}, seqno=#{inspect seq_no}")
                delivered = state.delivered[proc]
                all_up_to = state.all_up_to[proc]
                # IO.puts("#{inspect state.name}: delivered=#{inspect delivered}, all_up_to=#{inspect all_up_to}, seq_no=#{inspect seq_no}")

                # This is a new message
                if seq_no > all_up_to and seq_no not in delivered do
                    # IO.puts("#{inspect state.name}: New message: #{inspect m} from #{inspect proc}, seqno=#{inspect seq_no}")
                    delivered = MapSet.put(delivered, seq_no) # update delivered of proc with a new sequence number
                    {delivered, all_up_to} = compact_delivered(delivered, all_up_to)  # Try to compact delivered and update all_up_to
                    send(self(), {:deliver, proc, m}) # Triffer deliver indiciation
                    beb_broadcast({:data, proc, seq_no, m}, state.processes) # Rebroadcast the message to ensure Agreement

                    # Replace beb_broadcast above with the one below to
                    # simulate the scenario in which :p0 does not broadcast to :p0 and :p1, and
                    # no one broadcasts to :p0.
                    # beb_broadcast_with_failures(state.name, :p0, [:p0, :p1], data_msg, state.processes)
                    # beb_broadcast_with_failures(state.name, :p0, [:p0, :p1, :p2], {:data, proc, seq_no, m}, state.processes)

                    # IO.puts("#{inspect state.name}: Echo: #{inspect m} from #{inspect proc}, seqno=#{inspect seq_no}")

                    # Update the state to reflect updates to delivered and all_up_to
                    %{state | delivered: %{state.delivered | proc => delivered},
                              all_up_to: %{state.all_up_to | proc => all_up_to}}
                else
                    # IO.puts("#{inspect state.name}: Delivered before: #{inspect m} from #{inspect proc}, seqno=#{inspect seq_no}")
                    state
                end

            {:deliver, proc, m} ->
                IO.puts("#{inspect state.name}: RB-deliver: #{inspect m} from #{inspect proc}")
                state
        end
        run(state)
    end

    # Compute the next highest contiguous message sequence number in the set s
    # starting from seqno
    defp get_upper_seqno(seqno, s) do
        if seqno in s, do: get_upper_seqno(seqno + 1, s), else: seqno-1
    end

    # Try to compact the delivered set for a process
    # as per the algorithm described in the handout
    defp compact_delivered(delivered, all_up_to) do
        new_upper_seqno = get_upper_seqno(all_up_to + 1, delivered)
        if new_upper_seqno > all_up_to do
            delivered = Enum.reduce(all_up_to + 1..new_upper_seqno, delivered,
                    fn(sn, s) -> MapSet.delete(s, sn) end)
            all_up_to = new_upper_seqno
            {delivered, all_up_to}
        else
            {delivered, all_up_to}
        end
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

    # Simulate a scenario in which proct_to_fail fails to send the message m
    # to the processes in fail_send_to, and all other processes fail
    # to send to proc_to_fail
    defp beb_broadcast_with_failures(name, proc_to_fail, fail_send_to, m, dest) do
        if name == proc_to_fail do
            for p <- dest, p not in fail_send_to, do: unicast(m, p)
        else
            for p <- dest, p != proc_to_fail, do: unicast(m, p)
        end
    end

end
