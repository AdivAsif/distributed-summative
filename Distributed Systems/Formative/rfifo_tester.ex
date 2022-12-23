defmodule RfifoTester do

    @on_definition {TestHooks, :on_def}
    # Module.register_attribute(__MODULE__, :test_cases, accumulate: true)
    
    def receive_all(msgs, _, true), do: msgs
    def receive_all(msgs, pid_to_name, false) do
        receive do
            {:deliver, pid, proc, {:test, n}}=m ->
                # IO.puts("received: #{inspect m} pid: #{inspect pid} alive: #{inspect Process.alive?(pid)}")
                if Map.has_key?(pid_to_name, pid) do
                    # {:registered_name, rcvr} = Process.info(pid, :registered_name)
                    # IO.puts("process valid message #{inspect m}")
                    rcvr = pid_to_name[pid]
                    msgs = %{msgs | rcvr => [{proc, n} | msgs[rcvr]]}
                    receive_all(msgs, pid_to_name, false)
                else
                    IO.puts("ignoring message from a prior session #{inspect m}")
                    receive_all(msgs, pid_to_name, false)
                end
            m ->
                IO.puts("ignoring unexpected message #{inspect m}")
                receive_all(msgs, pid_to_name, false)
            after 10000 -> 
                receive_all(msgs, pid_to_name, true)
        end
        
    end

    def validity(sent, rcvd, correct) do
        Enum.all?(
            for p <- correct do
                Enum.all?(
                    for q <- correct do
                        recvd_by_q_from_p = Enum.filter(rcvd[q], fn({proc, _}) -> proc == p end)
                        MapSet.equal?(MapSet.new(Enum.filter(sent, fn({proc, _}) -> proc == p end)), 
                            MapSet.new(recvd_by_q_from_p))
                    end
                )
            end
        )
    end

    def no_dup(rcvd) do
        Enum.all?(
            for {_, msgs} <- rcvd do
                length(Enum.uniq(msgs)) == length(msgs)
            end
        )
    end

    def agreement(rcvd, correct) do
        length(
            Enum.uniq(
                for p <- correct do
                    MapSet.new(rcvd[p])
                end
            )
        ) == 1
    end

    def fifo(rcvd) do
        Enum.all?(
            for {_, msgs} <- rcvd do
                Enum.all?(
                    for {_, seqs} <- Enum.group_by(msgs, fn {p, _} -> p end, fn {_, n} -> n end) do
                        seqs == Enum.sort(seqs, :desc)
                    end
                )
            end
        )
    end

    def check(sent, rcvd, correct) do
        [ 
            validity: validity(sent, rcvd, correct), 
            no_duplication: no_dup(rcvd), 
            agreement: agreement(rcvd, correct), 
            fifo: fifo(rcvd)
        ]
    end

    def async_crash(pid, timeout) do
        spawn(fn -> 
                Process.sleep(timeout)
                send(pid, {:crash})
        end)
    end

    def async_fail(pid, timeout) do
        spawn(fn -> 
                Process.sleep(timeout)
                send(pid, {:fail})
        end)
    end

    def kill_proc(pid, name) do
        beb_name = String.to_atom(Atom.to_string(name) <> "_beb")
        # beb_pid = Process.whereis(beb_name)
        # if name in Process.registered, do: Process.unregister(name)
        # if beb_name in Process.registered, do: Process.unregister(beb_name)
        Process.monitor({name, Node.self})
        Process.monitor({beb_name, Node.self})
        Process.exit(pid, :kill)
        for n <- [name, beb_name] do
            receive do
                {:DOWN, _, :process, {^n, _}, _} -> n
            end 
        end
    end

    def monitor_procs(pids) do
        for p <- pids, do: Process.monitor(p)
    end

    @doc """
    No failures, one process broadcasts one message
    """
    def test_one_message() do
        procs = [:p1, :p2, :p3]
        # IO.puts("destination: #{inspect self()}")
        pid_to_name = for p <- procs, into: %{}, do: {ReliableFIFOBroadcast.start(p, procs, self()), p} 
        name_to_pid = for {pid, name} <- pid_to_name, into: %{}, do: {name, pid}
        try do
            send(name_to_pid[:p1], {:broadcast, {:test, 1}})
            # IO.puts("Sent broadcast via pid: #{inspect name_to_pid[:p1]}")
            msgs = receive_all((for p <- procs, into: %{}, do: {p, []}), pid_to_name, false)
            check(MapSet.new([{:p1, 1}]), msgs, procs)
        rescue
            e ->
                IO.puts("#{inspect e}")
                false
        after
            Enum.each(pid_to_name, fn {p, name} -> kill_proc(p, name) end)
        end
    end

    @doc """
    No failures, one process broadcasts multiple messages
    """
    def test_one_proc_many_messages() do
        procs = [:p1, :p2, :p3]
        # IO.puts("destination: #{inspect self()}")
        pid_to_name = for p <- procs, into: %{}, do: {ReliableFIFOBroadcast.start(p, procs, self()), p} 
        name_to_pid = for {pid, name} <- pid_to_name, into: %{}, do: {name, pid}
        try do
            sent = for i <- 1..5 do
                send(name_to_pid[:p1], {:broadcast, {:test, i}})
                {:p1, i}
            end           
            # IO.puts("Sent broadcast via pid: #{inspect name_to_pid[:p1]}")
            msgs = receive_all((for p <- procs, into: %{}, do: {p, []}), pid_to_name, false)
            check(MapSet.new(sent), msgs, procs)
        rescue
            e ->
                IO.puts("#{inspect e}")
                false
        after
            Enum.each(pid_to_name, fn {p, name} -> kill_proc(p, name) end)
        end
    end

    @doc """
    No failures, multiple processes broadcast multiple messages
    """ 
    def test_many_proc_many_messages() do
        procs = [:p1, :p2, :p3]
        # IO.puts("destination: #{inspect self()}")
        pid_to_name = for p <- procs, into: %{}, do: {ReliableFIFOBroadcast.start(p, procs, self()), p} 
        name_to_pid = for {pid, name} <- pid_to_name, into: %{}, do: {name, pid}
        try do
            sent = for i <- 1..15 do
                send(name_to_pid[(p=Enum.random(procs))], {:broadcast, {:test, i}})
                {p, i}
            end           
            # IO.puts("Sent broadcast via pid: #{inspect name_to_pid[:p1]}")
            msgs = receive_all((for p <- procs, into: %{}, do: {p, []}), pid_to_name, false)
            check(MapSet.new(sent), msgs, procs)
        rescue
            e ->
                IO.puts("#{inspect e}")
                false
        after
            Enum.each(pid_to_name, fn {p, name} -> kill_proc(p, name) end)
        end
    end

    @doc """
    A non-sender process crashes, one process broadcasts multiple messages
    """ 
    def test_one_proc_many_messages_non_sender_crash() do
        procs = [:p1, :p2, :p3, :p4]
        # IO.puts("destination: #{inspect self()}")
        pid_to_name = for p <- procs, into: %{}, do: {ReliableFIFOBroadcast.start(p, procs, self()), p} 
        name_to_pid = for {pid, name} <- pid_to_name, into: %{}, do: {name, pid}
        Process.sleep(2000)
        try do
            async_crash(Process.whereis(:p3_beb), Enum.random(1..500))
            sent = for i <- 1..15 do
                send(name_to_pid[(p=:p2)], {:broadcast, {:test, i}})
                {p, i}
            end
            sent = Enum.concat(sent, 
                for i <- 16..20 do
                   send(name_to_pid[(p=:p2)], {:broadcast, {:test, i}})
                    {p, i} 
                end
            )          
            # IO.puts("Sent broadcast via pid: #{inspect name_to_pid[:p1]}")
            msgs = receive_all((for p <- procs, into: %{}, do: {p, []}), pid_to_name, false)
            check(MapSet.new(sent), msgs, [:p1, :p2, :p4])
        rescue
            e ->
                IO.puts("#{inspect e}")
                false
        after
            Enum.each(pid_to_name, fn {p, name} -> kill_proc(p, name) end)
        end
    end

    @doc """
    A non-sender process crashes, multiple processes broadcast multiple messages
    """ 
    def test_many_proc_many_messages_non_sender_crash() do
        procs = [:p1, :p2, :p3, :p4]
        # IO.puts("destination: #{inspect self()}")
        pid_to_name = for p <- procs, into: %{}, do: {ReliableFIFOBroadcast.start(p, procs, self()), p} 
        name_to_pid = for {pid, name} <- pid_to_name, into: %{}, do: {name, pid}
        Process.sleep(2000)
        try do
            async_crash(Process.whereis(:p3_beb), Enum.random(500..1000))
            sent = for i <- 1..15 do
                send(name_to_pid[(p=Enum.random([:p1, :p2, :p4]))], {:broadcast, {:test, i}})
                {p, i}
            end
            sent = Enum.concat(sent, 
                for i <- 16..20 do
                   send(name_to_pid[(p=Enum.random([:p1, :p2, :p4]))], {:broadcast, {:test, i}})
                    {p, i} 
                end
            )          
            # IO.puts("Sent broadcast via pid: #{inspect name_to_pid[:p1]}")
            msgs = receive_all((for p <- procs, into: %{}, do: {p, []}), pid_to_name, false)
            check(MapSet.new(sent), msgs, [:p1, :p2, :p4])
        rescue
            e ->
                IO.puts("#{inspect e}")
                false
        after
            Enum.each(pid_to_name, fn {p, name} -> kill_proc(p, name) end)
        end
    end

    @doc """
    Several non-sender processes crash, multiple processes broadcast multiple messages
    """
    def test_many_proc_many_messages_non_sender_crash2() do
        procs = [:p1, :p2, :p3, :p4]
        # IO.puts("destination: #{inspect self()}")
        pid_to_name = for p <- procs, into: %{}, do: {ReliableFIFOBroadcast.start(p, procs, self()), p} 
        name_to_pid = for {pid, name} <- pid_to_name, into: %{}, do: {name, pid}
        Process.sleep(2000)
        try do
            async_crash(Process.whereis(:p3_beb), Enum.random(500..1000))
            async_crash(Process.whereis(:p4_beb), Enum.random(500..1000))
            sent = for i <- 1..15 do
                send(name_to_pid[(p=Enum.random([:p1, :p2]))], {:broadcast, {:test, i}})
                {p, i}
            end
            sent = Enum.concat(sent, 
                for i <- 16..20 do
                   send(name_to_pid[(p=Enum.random([:p1, :p2]))], {:broadcast, {:test, i}})
                    {p, i} 
                end
            )          
            # IO.puts("Sent broadcast via pid: #{inspect name_to_pid[:p1]}")
            msgs = receive_all((for p <- procs, into: %{}, do: {p, []}), pid_to_name, false)
            check(MapSet.new(sent), msgs, [:p1, :p2])
        rescue
            e ->
                IO.puts("#{inspect e}")
                false
        after
            Enum.each(pid_to_name, fn {p, name} -> kill_proc(p, name) end)
        end
    end

    @doc """
    No failures, one process broadcasts multiple messages
    """
    def test_one_proc_many_messages_reorder() do
        procs = [:p1, :p2, :p3]
        # IO.puts("destination: #{inspect self()}")
        pid_to_name = for p <- procs, into: %{}, do: {ReliableFIFOBroadcast.start(p, procs, self()), p} 
        name_to_pid = for {pid, name} <- pid_to_name, into: %{}, do: {name, pid}
        Process.sleep(2000)
        BestEffortBroadcast.change_bcast_type(Process.whereis(:p1_beb), :reorder)
        BestEffortBroadcast.change_bcast_type(Process.whereis(:p2_beb), :reorder)
        BestEffortBroadcast.change_bcast_type(Process.whereis(:p3_beb), :reorder)
        try do
            sent = for i <- 1..20 do
                send(name_to_pid[(p=:p2)], {:broadcast, {:test, i}})
                {p, i}
            end           
            # IO.puts("Sent broadcast via pid: #{inspect name_to_pid[:p1]}")
            msgs = receive_all((for p <- procs, into: %{}, do: {p, []}), pid_to_name, false)
            check(MapSet.new(sent), msgs, procs)
        rescue
            e ->
                IO.puts("#{inspect e}")
                false
        after
            Enum.each(pid_to_name, fn {p, name} -> kill_proc(p, name) end)
        end
    end

    @doc """
    No failures, multiple processes broadcast multiple messages
    """
    def test_many_proc_many_messages_reorder() do
        procs = [:p1, :p2, :p3]
        # IO.puts("destination: #{inspect self()}")
        pid_to_name = for p <- procs, into: %{}, do: {ReliableFIFOBroadcast.start(p, procs, self()), p} 
        name_to_pid = for {pid, name} <- pid_to_name, into: %{}, do: {name, pid}
        Process.sleep(2000)
        BestEffortBroadcast.change_bcast_type(Process.whereis(:p1_beb), :reorder)
        BestEffortBroadcast.change_bcast_type(Process.whereis(:p2_beb), :reorder)
        BestEffortBroadcast.change_bcast_type(Process.whereis(:p3_beb), :reorder)
        try do
            sent = for i <- 1..15 do
                send(name_to_pid[(p=Enum.random(procs))], {:broadcast, {:test, i}})
                {p, i}
            end           
            # IO.puts("Sent broadcast via pid: #{inspect name_to_pid[:p1]}")
            msgs = receive_all((for p <- procs, into: %{}, do: {p, []}), pid_to_name, false)
            check(MapSet.new(sent), msgs, procs)
        rescue
            e ->
                IO.puts("#{inspect e}")
                false
        after
            Enum.each(pid_to_name, fn {p, name} -> kill_proc(p, name) end)
        end
    end

    @doc """
    One process broadcasts one message and fails while beb-broadcasting a message
    """
    def test_one_message_with_fail() do
        procs = [:p1, :p2, :p3]
        # IO.puts("destination: #{inspect self()}")
        pid_to_name = for p <- procs, into: %{}, do: {ReliableFIFOBroadcast.start(p, procs, self()), p} 
        name_to_pid = for {pid, name} <- pid_to_name, into: %{}, do: {name, pid}
        Process.sleep(2000)
        BestEffortBroadcast.fail(Process.whereis(:p1_beb))
        try do
            send(name_to_pid[:p1], {:broadcast, {:test, 1}})
            # IO.puts("Sent broadcast via pid: #{inspect name_to_pid[:p1]}")
            msgs = receive_all((for p <- procs, into: %{}, do: {p, []}), pid_to_name, false)
            check(MapSet.new([{:p1, 1}]), msgs, [:p2, :p3])
        rescue
            e ->
                IO.puts("#{inspect e}")
                false
        after
            Enum.each(pid_to_name, fn {p, name} -> kill_proc(p, name) end)
        end
    end

    @doc """
    One process broadcasts multiple messages and fails while beb-broadcasting a message
    """
    def test_one_proc_many_messages_with_fail() do
        procs = [:p1, :p2, :p3]
        # IO.puts("destination: #{inspect self()}")
        pid_to_name = for p <- procs, into: %{}, do: {ReliableFIFOBroadcast.start(p, procs, self()), p} 
        name_to_pid = for {pid, name} <- pid_to_name, into: %{}, do: {name, pid}
        Process.sleep(2000)
        try do
            async_fail(Process.whereis(:p1_beb), Enum.random(1..100))
            sent = for i <- 1..50 do
                send(name_to_pid[:p1], {:broadcast, {:test, i}})
                Process.sleep(Enum.random(1..2))
                {:p1, i}
            end           
            # IO.puts("Sent broadcast via pid: #{inspect name_to_pid[:p1]}")
            msgs = receive_all((for p <- procs, into: %{}, do: {p, []}), pid_to_name, false)
            # IO.puts "#{inspect msgs}"
            check(MapSet.new(sent), msgs, [:p2, :p3])
        rescue
            e ->
                IO.puts("#{inspect e}")
                false
        after
            Enum.each(pid_to_name, fn {p, name} -> kill_proc(p, name) end)
        end
    end

    @doc """
    Multiple processes broadcast multiple messages and some processes fail 
    while beb-broadcasting some messages
    """
    def test_many_proc_many_messages_with_fail() do
        procs = [:p1, :p2, :p3, :p4, :p5]
        # IO.puts("destination: #{inspect self()}")
        pid_to_name = for p <- procs, into: %{}, do: {ReliableFIFOBroadcast.start(p, procs, self()), p} 
        name_to_pid = for {pid, name} <- pid_to_name, into: %{}, do: {name, pid}
        Process.sleep(2000)
        try do
            async_fail(Process.whereis(:p2_beb), Enum.random(1..100))
            async_fail(Process.whereis(:p5_beb), Enum.random(1..100))
            sent = for i <- 1..50 do
                send(name_to_pid[(p=Enum.random(procs))], {:broadcast, {:test, i}})
                Process.sleep(Enum.random(1..2))
                {p, i}
            end           
            # IO.puts("Sent broadcast via pid: #{inspect name_to_pid[:p1]}")
            msgs = receive_all((for p <- procs, into: %{}, do: {p, []}), pid_to_name, false)
            # IO.puts "#{inspect msgs}"
            check(MapSet.new(sent), msgs, [:p1, :p3, :p4])
        rescue
            e ->
                IO.puts("#{inspect e}")
                false
        after
            Enum.each(pid_to_name, fn {p, name} -> kill_proc(p, name) end)
        end
    end

    @doc """
    Multiple processes broadcast multiple messages, some processes fail while 
    beb-broadcasting some messages, some messages are re-ordered by the Best-Effort Broadcast layer
    """
    def test_many_proc_many_messages_with_fail_reorder() do
        procs = [:p1, :p2, :p3, :p4, :p5]
        # IO.puts("destination: #{inspect self()}")
        pid_to_name = for p <- procs, into: %{}, do: {ReliableFIFOBroadcast.start(p, procs, self()), p} 
        name_to_pid = for {pid, name} <- pid_to_name, into: %{}, do: {name, pid}
        Process.sleep(2000)
        try do
            BestEffortBroadcast.change_bcast_type(Process.whereis(:p2_beb), :reorder)
            BestEffortBroadcast.change_bcast_type(Process.whereis(:p3_beb), :reorder)
            BestEffortBroadcast.change_bcast_type(Process.whereis(:p4_beb), :reorder)
            async_fail(Process.whereis(:p2_beb), Enum.random(1..100))
            async_fail(Process.whereis(:p5_beb), Enum.random(1..100))
            sent = for i <- 1..100 do
                send(name_to_pid[(p=Enum.random(procs))], {:broadcast, {:test, i}})
                Process.sleep(Enum.random(1..2))
                {p, i}
            end           
            # IO.puts("Sent broadcast via pid: #{inspect name_to_pid[:p1]}")
            msgs = receive_all((for p <- procs, into: %{}, do: {p, []}), pid_to_name, false)
            # IO.puts "#{inspect msgs}"
            check(MapSet.new(sent), msgs, [:p1, :p3, :p4])
        rescue
            e ->
                IO.puts("#{inspect e}")
                false
        after
            Enum.each(pid_to_name, fn {p, name} -> kill_proc(p, name) end)
        end
    end

    def run_all_tests() do
        # IO.puts "#{inspect @test_cases}"
        # for {f, _} <- RfifoTester.__info__(:functions), String.starts_with?(Atom.to_string(f), "test_") do
        for {f, doc} <- @test_cases do
            IO.puts("TEST: #{doc}")
            res = apply(RfifoTester, f, [])
            pass_or_fail = if Enum.all?(for {_, r} <- res, do: r), do: "PASS", else: "FAIL"
            IO.puts("\t#{pass_or_fail}")
            IO.puts("\t#{inspect res}")
            IO.puts("\n")
            # Process.sleep(1000)
        end
    end

    def get_test_info() do
        @test_cases
    end

    def print_test_info() do
        for {f, doc} <- @test_cases do
            IO.puts("#{f}: \"#{doc}\"")
        end

    end

end