IEx.Helpers.c("paxos.ex", ".")
# IEx.Helpers.c("account_server.ex", ".")
IEx.Helpers.c("airline_reservation.ex", ".")
procs = [:p1, :p2, :p3]
pids = Enum.map(procs, fn p -> Paxos.start(p, procs) end)
# Paxos.propose(:global.whereis_name(:p3), 1, {:hello, "world"}, 1000)
# Paxos.propose(:global.whereis_name(:p2), 2, {:hola, "world"}, 1000)
# Paxos.propose(:global.whereis_name(:p1), 3, {:bye, "world"}, 1000)
# IO.puts("#{inspect(Paxos.get_decision(:global.whereis_name(:p3), 3, 1000))}")

# a = AccountServer.start(:server1, :p1)
# AccountServer.deposit(a, 10)
# AccountServer.withdraw(a, 5)
# IO.puts("#{inspect AccountServer.balance(a)}")

s = SeatReservation.start(:server1, :p1)
SeatReservation.occupy(s, :a1)
IO.puts("Seats state: #{inspect SeatReservation.get_seats(s)}")

Enum.each(pids, fn p -> Process.exit(p, :kill) end)
:os.cmd('/bin/rm -f *.beam')
Node.stop()
System.halt()
