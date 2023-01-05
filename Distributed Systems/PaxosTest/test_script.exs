:os.cmd('/bin/rm -f *.beam')

IEx.Helpers.c("test_harness.ex")
IEx.Helpers.c("paxos_test.ex")
IEx.Helpers.c("uuid.ex")

# Replace with your own implementation source files
# IEx.Helpers.c("beb.ex")
IEx.Helpers.c("paxos.ex")
# ##########

# Replace the following with the short host name of your machine
host = "elixir"
# ###########

get_node = fn -> String.to_atom(UUID.uuid1() <> "@" <> host) end

# Use get_dist_config.(n) to generate a multi-node configuration
# consisting of n processes, each one on a different node
get_dist_config = fn n ->
  for i <- 1..n,
      into: %{},
      do: {String.to_atom("p" <> to_string(i)), {get_node.(), {:val, 100 + i}}}
end

# Use get_local_config.(n) to generate a single-node configuration
# consisting of n processes, all running on the same node
get_local_config = fn n ->
  for i <- 1..n, into: %{}, do: {String.to_atom("p" <> to_string(i)), {:local, {:val, 100 + i}}}
end

test_suite = [
  #   test case, configuration, number of times to run the case, description
  {&PaxosTest.run_simple/3, get_local_config.(3), 1, "No failures, no concurrent ballots"},
  {&PaxosTest.run_simple_2/3, get_local_config.(3), 1, "No failures, 2 concurrent ballots"},
  {&PaxosTest.run_simple_many/3, get_local_config.(5), 1, "No failures, many concurrent ballots"},
  {&PaxosTest.run_non_leader_crash/3, get_local_config.(3), 1,
   "One non-leader crashes, no concurrent ballots"},
  {&PaxosTest.run_minority_non_leader_crash/3, get_local_config.(5), 1,
   "Minority non-leader crashes, no concurrent ballots"},
  {&PaxosTest.run_leader_crash_simple/3, get_local_config.(5), 1,
   "Leader crashes, no concurrent ballots"},
  {&PaxosTest.run_leader_crash_simple_2/3, get_local_config.(7), 5,
   "Leader and some non-leaders crash, no concurrent ballots"},
  {&PaxosTest.run_leader_crash_complex/3, get_local_config.(11), 10,
   "Cascading failures of leaders and non-leaders"},
  {&PaxosTest.run_leader_crash_complex_2/3, get_local_config.(11), 1,
   "Cascading failures of leaders and non-leaders, random delays"}
]

Node.stop()
Node.start(get_node.(), :shortnames)

Enum.reduce(test_suite, length(test_suite), fn {func, config, n, doc}, acc ->
  IO.puts("============")
  IO.puts("#{inspect(doc)}, #{inspect(n)} time#{if n > 1, do: "s", else: ""}")
  IO.puts("============")
  for _ <- 1..n, do: TestHarness.test(func, Enum.shuffle(Map.to_list(config)))
  IO.puts("============#{if acc > 1, do: "\n", else: ""}")
  acc - 1
end)

Node.stop()
System.halt()
