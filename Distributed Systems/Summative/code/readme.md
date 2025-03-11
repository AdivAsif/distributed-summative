The API for my service is stored inside my_app and was implemented using the Phoenix framework. It's a basic Seat Reservation system that initially has 6 seats free, from seat a1 to b3, and allows users to occupy any free seat. This is run by calling occupy/2, which takes the id of the sender/client, and seat atom as arguments. Once a seat has been occupied, it cannot be withdrawn. There is also a get_seats/1 method which takes the id of the sender/client as an argument and returns the state of seats, once a seat has been occupied that seat is marked with an :occupied atom instead of a :free one.

Safety properties:
1. Mutual exclusion - the API utilises the Paxos implementation to ensure there cannot be a double booking, if there are two propositions made to occupy a seat at the same time and instance, then one user would receive an :ok message, while the other a :fail message, since the Paxos decision would result in :abort for one of the propositions, and succeed for the other.

2. The state of seats is returned by the frontend everytime occupy is called for a client, and also obviously the API and frontend only allow for booking existing seats, and not making them up. So it is guaranteed that the available seats are accurate as the state is constantly returned after being occupied.

Liveness properties:
1. The implementation of the Paxos algorithm being used is slightly different to the one used in the tests as it includes leader election, which helps prevent livelock as there is only one proposer at a time, so there should not be a case where the system is stuck in a loop, deciding on something.

2. The Paxos protocol enables termination, assuming at most a minority of replicas can fail, so a reservation will eventually be decided upon, meaning if a user clicks to occupy a free seat, then that seat will be occupied eventually.

To run the API, cd into my_app, and run "mix phx.server", this should run the API on port 4000, at http://localhost:4000/
To run the frontend, cd into SeatReservation and run "dotnet run", this should run the portal on port 5237, at http://localhost:5237/
This assumes that up to a minority can crash, although while running this, none crash so at all times there is a majority that can agree on a value, it also assumes that all sender names, aka names of processes are unique so that ballots are unique, where in reality this may not always be the case. For the frontend to run, it also assumes that the API is running beforehand, and on port 4000.
It also assumes that the latest .NET version, as well as Elixir is installed.
Initially when running the app, all seats will be highlighted red, it is just initialising the state of seats, it will eventually all turn unhighlighted. When clicking a seat, it may take a couple seconds to register that it has been occupied, this is just the API taking time to return a value.