defmodule ListModule do
    def sum_square([]), do: 0
    def sum_square([h | t]), do: h*h + sum_square(t)
    
    def len([]), do: 0
    def len([h | t]), do: 1 + len(t)
    
    def reverse([]), do: []
    def reverse([h | t]), do: reverse(t) ++ [h]
end