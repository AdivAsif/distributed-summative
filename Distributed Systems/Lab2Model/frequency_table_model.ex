defmodule FrequencyTable do
    def update_freq(key, dict), do: if Map.has_key?(dict, key), do: %{dict | key => dict[key] + 1},
                                    else: Map.put_new(dict, key, 1)


    # Tail-recursive freq_count
    def freq_count(lst), do: do_freq_count(lst, %{})
    defp do_freq_count([], res), do: res
    defp do_freq_count([h | t], res), do: do_freq_count(t, update_freq(h, res))

    # Another tail-recursive freq_count using Enum.reduce
    def freq_count2(lst), do: Enum.reduce(lst, %{}, &update_freq/2)

    # Non-tail-recursive freq_count
    def freq_count3([]), do: %{}
    def freq_count3([h | t]), do: update_freq(h, freq_count3(t))

    @poem "
        Row, row, row your boat
        Gently down the stream
        Merrily, merrily, merrily, merrily
        Life is but a dream
        "
    def get_poem_1, do: @poem

    @poem "
    He don't like to pillage.
    He don't like to rob.
    He don't like to bury his treasure.
    He don't like to shoot
    or to ransack and loot
    or commandeer ships for his pleasure
    "
    def get_poem_2, do: @poem

    @poem "
    This is the house that Jack built.
    This is the malt that lay in the house that Jack built.
    This is the rat that ate the malt
    That lay in the house that Jack built.
    This is the cat
    That killed the rat that ate the malt
    That lay in the house that Jack built.
    This is the dog that worried the cat
    That killed the rat that ate the malt
    That lay in the house that Jack built.
    "
    def get_poem_3, do: @poem

    def word_count(text), do:
        text |>
        String.split(~r{\W+}, trim: true) |>
        Enum.map(fn(x) -> String.downcase(x) end) |>
        freq_count3

    def swap_map(map) do
        for {k, v} <- map, do: {v, k}
    end

    def to_histogram(dict) do
        total = Enum.reduce(dict, 0, fn({_, v}, y) -> v + y end)
        (for {item, freq} <- dict, do: {div(freq * 100, total), item}) |>
        Enum.sort(fn({x, _}, {y, _}) -> x > y end)
    end

    # Solution to Exercise 13: either uncomment and run the file, or copy/paste and run from IEX
    FrequencyTable.get_poem_1 |> FrequencyTable.word_count |> FrequencyTable.to_histogram |> IO.inspect
    # FrequencyTable.get_poem_2 |> FrequencyTable.word_count |> FrequencyTable.to_histogram |> IO.inspect
    # FrequencyTable.get_poem_3 |> FrequencyTable.word_count |> FrequencyTable.to_histogram |> IO.inspect


end
