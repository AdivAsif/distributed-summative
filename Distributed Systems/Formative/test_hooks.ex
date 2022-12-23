defmodule TestHooks do
    def on_def(_env, _kind, name, _args, _guards, _body) do
        if String.starts_with?(Atom.to_string(name), "test_") do
            # IO.puts("Defining test #{name}")
            {_, doc} = Module.get_attribute(RfifoTester, :doc)
            doc = String.trim(doc)
            if Module.has_attribute?(RfifoTester, :test_cases) do
                Module.put_attribute(RfifoTester, :test_cases, Module.get_attribute(RfifoTester, :test_cases) ++ [{name, doc}])
            else
                Module.put_attribute(RfifoTester, :test_cases, [{name, doc}])
            end
        end
        # IO.inspect(args)
        # IO.puts("and guards")
        # IO.inspect(guards)
        # IO.puts("and body")
        # IO.puts(Macro.to_string(body))
    end

end