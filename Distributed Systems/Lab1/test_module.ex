defmodule TestModule do
  def fact(0), do: 1
  def fact(n) when n >= 0 do
    n * fact(n - 1)
  end
end
