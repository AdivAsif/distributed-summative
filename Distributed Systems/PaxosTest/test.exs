IEx.Helpers.c("paxos.ex")

procs = [:p1, :p2, :p3]
pids = Enum.map(procs, fn p -> Paxos.start(p, procs, self()) end)
# propose = Paxos.propose(:global.whereis_name(:p3), {:hello, "world"})
# IO.puts("Propose value: #{inspect propose}")
# start_ballot = Paxos.start_ballot(:global.whereis_name(:p3))
# IO.puts("Start Ballot value: #{inspect start_ballot}")

# pid1 = Paxos.start(:p1, [:p1, :p2, :p3], self())
# pid2 = Paxos.start(:p2, [:p1, :p2, :p3], self())
# pid3 = Paxos.start(:p3, [:p1, :p2, :p3], self())

for {p, v} <- [{:global.whereis_name(:p1), :a}, {:global.whereis_name(:p2), :b}, {:global.whereis_name(:p3), :c}], do: Paxos.propose(p, v)

Paxos.start_ballot(:global.whereis_name(:p1))

for _ <- 1..3 do
  receive do
    {:decide, value} ->
      IO.puts(value)
  after
    10000 -> IO.puts("Timeout")
  end
end

Process.exit(:global.whereis_name(:p1), :kill)
Process.exit(:global.whereis_name(:p2), :kill)
Process.exit(:global.whereis_name(:p3), :kill)

Process.exit(self(), :kill)

:os.cmd('/bin/rm -f *.beam')
Node.stop
System.halt
