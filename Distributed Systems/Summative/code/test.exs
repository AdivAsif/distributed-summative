# # IEx.Helpers.c "paxos.ex", "."
# IEx.Helpers.c "thepaxos.ex", "."
# procs = [:p1, :p2, :p3]
# pids = Enum.map(procs, fn p -> Paxos.start(p, procs) end)
# Paxos.propose(:global.whereis_name(:p3), 1, {:hello, "world"}, 1000)
# # IO.puts("Test Propose value: #{inspect propose}")
# Paxos.get_decision(:global.whereis_name(:p3), 1, 1000)
# # IO.puts("Test Decided value: #{inspect decision}")
# IO.puts("Decision: #{inspect Paxos.get_decision(:global.whereis_name(:p3), 1, 1000)}")
# send(Enum.at(pids, 2), {:print_state})
# :os.cmd('/bin/rm -f *.beam')
# Node.stop
# System.halt

IEx.Helpers.c "thepaxos.ex", "."
procs = [:p1, :p2, :p3]
pids = Enum.map(procs, fn p -> Paxos.start(p, procs) end)
p_fun = fn n, i, v, t -> (fn -> Paxos.propose(:global.whereis_name(n), i, v, t) end) end
spawn(p_fun.(:p3, 1, :hola, 500)); spawn(p_fun.(:p2, 2, :hi, 500))
:timer.sleep(3000)
# IO.puts("Test Propose value: #{inspect propose}")
# IO.puts("Test Decided value: #{inspect decision}")
IO.puts("P1 Decision: #{inspect Paxos.get_decision(:global.whereis_name(:p1), 1, 1000)}")
IO.puts("P3 Decision: #{inspect Paxos.get_decision(:global.whereis_name(:p3), 2, 1000)}")
send(Enum.at(pids, 1), {:print_state})
:os.cmd('/bin/rm -f *.beam')
Node.stop
System.halt
