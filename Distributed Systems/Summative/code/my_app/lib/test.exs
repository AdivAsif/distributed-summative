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

s1 = SeatReservation.start(:server1, :p1)
s2 = SeatReservation.start(:server2, :p2)
s3 = SeatReservation.start(:server3, :p3)
p_fun = fn n, seat -> (fn -> SeatReservation.occupy(:global.whereis_name(n), seat) end) end
spawn(p_fun.(:server1, :a2)); spawn(p_fun.(:server2, :a1)); spawn(p_fun.(:server3, :b3))
:timer.sleep(10000)
IO.puts("Seats state for server 1: #{inspect SeatReservation.get_seats(s1)}")
IO.puts("Seats state for server 2: #{inspect SeatReservation.get_seats(s2)}")
IO.puts("Seats state for server 3: #{inspect SeatReservation.get_seats(s3)}")

Enum.each(pids, fn p -> Process.exit(p, :kill) end)
:os.cmd('/bin/rm -f *.beam')
Node.stop()
System.halt()
