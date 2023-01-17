# IEx.Helpers.c "paxos.ex", "."
IEx.Helpers.c "thepaxos.ex", "."
procs = [:p1, :p2, :p3]
pids = Enum.map(procs, fn p -> Paxos.start(p, procs) end)
Paxos.propose(:global.whereis_name(:p3), 1, {:hello, "world"}, 1000)
# IO.puts("Test Propose value: #{inspect propose}")
Paxos.get_decision(:global.whereis_name(:p3), 1, 1000)
# IO.puts("Test Decided value: #{inspect decision}")
IO.puts("#{inspect Paxos.get_decision(:global.whereis_name(:p3), 1, 1000)}")
send(Enum.at(pids, 2), {:print_state})
:os.cmd('/bin/rm -f *.beam')
Node.stop
System.halt
