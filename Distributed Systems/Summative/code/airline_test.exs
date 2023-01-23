# IEx.Helpers.c "paxos.ex", "."
IEx.Helpers.c "paxos.ex", "."
IEx.Helpers.c "airline_reservation.ex", "."
procs = [:p1, :p2, :p3]
pids = Enum.map(procs, fn p -> Paxos.start(p, procs) end)
a = SeatReservation.start(:server1, :p1)
b = SeatReservation.start(:server2, :p2)
c = SeatReservation.start(:server3, :p3)
SeatReservation.occupy(a, :a1)
SeatReservation.occupy(b, :b1)
SeatReservation.occupy(c, :a2)
:timer.sleep(3000)
SeatReservation.get_seats(c)
:os.cmd('/bin/rm -f *.beam')
Node.stop
System.halt
