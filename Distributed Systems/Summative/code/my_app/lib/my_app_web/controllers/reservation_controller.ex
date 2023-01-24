defmodule MyAppWeb.ReservationController do
  use MyAppWeb, :controller
  procs = [:p1, :p2, :p3]
  pids = Enum.map(procs, fn p -> Paxos.start(p, procs) end)
  a = SeatReservation.start(:server1, :p1)

  def occupy(conn, %{"seat" => seat}) do
    decision =
      SeatReservation.occupy(:global.whereis_name(:server1), String.to_existing_atom(seat))

    IO.puts("#{inspect(decision)}")

    json(conn, %{decision: decision})
  end

  def get_seats(conn, %{"name" => name}) do
    seats = SeatReservation.get_seats(:global.whereis_name(String.to_existing_atom(name)))
    json(conn, %{seats: seats})
  end
end
