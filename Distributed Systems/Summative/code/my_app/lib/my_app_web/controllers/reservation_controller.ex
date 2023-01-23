defmodule MyAppWeb.ReservationController do
  use MyAppWeb, :controller

  def occupy(conn, %{"seat" => seat}) do
    procs = [:p1, :p2, :p3]
    pids = Enum.map(procs, fn p -> Paxos.start(p, procs) end)
    a = SeatReservation.start(:server1, :p1)
    decision = SeatReservation.occupy(a, seat)
    IO.puts("#{inspect decision}")

    json(conn, %{decision: decision})
  end

  def get_seats(conn, %{"name" => name}) do
    IO.puts("#{inspect :global.whereis_name(name)}")
    seats = SeatReservation.get_seats(name)

    json(conn, %{seats: seats})
  end
end
