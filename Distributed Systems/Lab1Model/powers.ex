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
    def square_or_cube(n, p) when p == 3 do
        cube(n)
    end
    def square_or_cube(_, _) do
        :error
    end

    def pow(_, 0), do: 1 
    def pow(x, n) when is_integer(n) and n >= 0 do
        x * pow(x, n-1)
    end
    def pow(x, n) when is_integer(n) and n < 0 do
        pow(1/x, abs(n))
    end
    def pow(_, _) do
        :error
    end

end