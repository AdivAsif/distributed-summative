IEx.Helpers.c "paxos.ex", "."
IEx.Helpers.c "account_server.ex", "."
procs = [:p1, :p2, :p3]
pids = Enum.map(procs, fn p -> Paxos.start(p, procs) end)
a = AccountServer.start(:server1, :p1)
AccountServer.deposit(a, 10)
AccountServer.withdraw(a, 5)
IO.puts("#{inspect AccountServer.balance(a)}")
:os.cmd('/bin/rm -f *.beam')
Node.stop
System.halt
