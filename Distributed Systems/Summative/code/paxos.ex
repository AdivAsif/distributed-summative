defmodule Paxos do
  def start(name, participants) do
    pid = spawn(Paxos, :init, [name, participants])
    case :global.re_register_name(name, pid) do
      :yes -> pid
      :no -> :error
    end
    IO.puts "registered #{name}"
    pid
  end

  def propose(pid, inst, value, t) do

  end

  def get_decision(pid, inst, t) do

  end
end
