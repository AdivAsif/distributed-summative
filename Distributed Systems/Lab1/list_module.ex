defmodule ListModule do
  def sum_square([]), do: 0
  def sum_square([head | tail]), do: square(head) + sum_square(tail)
  defp square(n), do: n * n

  def sum([head | tail]), do: do_sum([head | tail], 0)
  defp do_sum([], result), do: result
  defp do_sum([head | tail], result) do
    do_sum(tail, head + result)
  end

  def len([head | tail]), do: do_len([head | tail], 0)
  defp do_len([], result), do: result
  defp do_len([_ | tail], result), do: do_len(tail, result + 1)

  def reverse([head | tail]), do: do_reverse([head | tail], [])
  defp do_reverse([], result), do: result
  defp do_reverse([head | tail], result), do: do_reverse(tail, [head | result])

  def span(from, to) when from > to, do: []
  def span(from, to), do: [from | span(from + 1, to)]

  def span_tr(from, to), do: do_span(from, to, [])
  defp do_span(from, to, result) when from > to, do: result
  defp do_span(from, to, result), do: do_span(from, to - 1, [to | result])

  def square_list(any), do: Enum.map(any, fn x -> square(x) end)

  def filter3(any), do: Enum.filter(any, fn x -> rem(x, 3) == 0 end)

  def square_and_filter3(any) do
    any |>
    square_list() |>
    filter3() |>
    IO.inspect(charlists: :as_lists)
  end

  def square_list_comp(any), do: for x <- any, do: square(x)

  def filter3_comp(any), do: for x <- any, do: if rem(x, 3) == 0, do: x, else: :_

  def square_and_filter3_comp(any), do: for x <- any, do: if rem(x, 3) == 0, do: square(x), else: :_

  def sum_red(any), do: Enum.reduce(any, 0, fn (x, y) -> x + y end)

  def len_red(any), do: Enum.reduce(any, 0, fn (_, y) -> y + 1 end)

  def reverse_red(any), do: Enum.reduce(any, [], fn(x, y) -> [x] ++ y end)

  def flatten([]), do: []
  def flatten([head | tail]), do: flatten(head) ++ flatten(tail)
  def flatten(any), do: [any]

  def flatten_tr(any) do

  end
  defp do_flatten()
end
