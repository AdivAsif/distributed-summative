defmodule Powers do
  def square(n) do
    n * n
  end

  def cube(n) do
    n * square(n)
  end

  def square_or_cube(n, p) when p == 2 do
    square(n)
  end

  def square_or_cube(n, 3) do
    cube(n)
  end

  def square_or_cube(_, _) do
    :error
  end

  def pow(_, p) when is_integer(p) == false, do: :error
  def pow(n, p) when p < 0, do: pow(n, abs(p))
  def pow(_, 0), do: 1
  def pow(n, p) when rem(p, 2) == 1, do: n * pow(n, p - 1)
  def pow(n, p) when p > 0 do
    result = pow(n, div(p, 2))
    result * result
  end
end
