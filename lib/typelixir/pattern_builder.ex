defmodule Typelixir.PatternBuilder do

  alias Typelixir.{TypeComparator}

  # ---------------------------------------------------------------------------------------------------
  # type -> returns the type of types defined on @spec
  #      -> returns the type of any pattern

  def type({:list, _, [type]}, env), do: {:list, type(type, env)}

  def type({:tuple, _, [types_list]}, env), do: {:tuple, Enum.map(types_list, fn type -> type(type, env) end)}

  def type({:map, _, [key_type, value_type]}, env), do: {:map, {type(key_type, env), type(value_type, env)}}

  def type({:_, _, _}, _env), do: :any

  # @spec
  def type({type, _, _}, _env) when (type in [:string, :boolean, :integer, :float, :atom, :any, :none]), do: type

  # tuple more 2 elems
  def type({:{}, _, list}, env), do: {:tuple, Enum.map(list, fn t -> type(t, env) end)}

  # map
  def type({:%{}, _, []}, _env), do: {:map, {:any, :any}}

  def type({:%{}, _, list}, env) do
    keys_values = Enum.map(list, fn {key, elem} -> {type(key, env), type(elem, env)} end)
    {:map, {
      elem(Enum.reduce(keys_values, fn {k_acc, _}, {k_e, _} -> {TypeComparator.supremum(k_acc, k_e), :_} end), 0),
      Enum.map(keys_values, fn {_, v} -> v end)
    }}
  end

  def type({:|, _, [operand1, operand2]}, env),
    do: {:list, TypeComparator.supremum(type(operand1, env), type(operand2, env))}

  # binding
  def type({:=, _, [operand1, operand2]}, env), do: TypeComparator.supremum(type(operand1, env), type(operand2, env))

  # variables
  def type({value, _, _}, env) do
    case env[:vars][value] do
      nil -> :any
      type -> type
    end
  end

  # list
  def type([], _env), do: {:list, :any}

  def type(value, env) when is_list(value),
    do: {:list, TypeComparator.supremum(Enum.map(value, fn t -> type(t, env) end))}

  # tuple 2 elems
  def type(value, env) when is_tuple(value),
    do: {:tuple, Enum.map(Tuple.to_list(value), fn t -> type(t, env) end)}

  # literals
  def type(value, _env) do
    cond do
      value === nil -> :atom
      is_boolean(value) -> :boolean
      is_bitstring(value) -> :string
      is_integer(value) -> :integer
      is_float(value) -> :float
      is_atom(value) -> :atom
      true -> :any
    end
  end

  # ---------------------------------------------------------------------------------------------------
  # vars -> returns a map with the vars of params and the corresponding types of
  # param_type_list, or {:error, "message"}

  def vars(params, param_type_list) do
    new_vars =
      Enum.zip(params, param_type_list)
      |> Enum.map(fn {var, type} -> get_vars(var, type) end)
      |> List.flatten()

    case new_vars[:error] do
      nil ->
        Enum.reduce_while(new_vars, %{}, fn {var, type}, acc ->
          t = Map.get(acc, var)
          cond do
            t === nil or t === type -> {:cont, Map.put(acc, var, type)}
            true -> {:halt, {:error, "Variable #{var} is already defined with type #{t}"}}
          end
        end)
      message -> {:error, message}
    end
  end

  defp get_vars(_, :any), do: []

  defp get_vars({op, _, _}, type) when (op not in [:{}, :%{}, :=, :_, :|]), do: {op, type}

  defp get_vars({:_, _, _}, _type), do: []

  defp get_vars({:=, _, [operand1, operand2]}, type),
    do: [get_vars(operand1, type), get_vars(operand2, type)]

  defp get_vars([], {:list, _type}), do: []

  # Todo: Fix this
  #   + func3([head|tail]) comes with [ {:|, [line: 25], [{:head, [line: 25], nil}, {:tail, [line: 25], nil}]} ]
  #        not with {:|, [line: 25], [{:head, [line: 25], nil}, {:tail, [line: 25], nil}]}
  #
  #     아래 함수가 이 점을 고려한 함수인 것으로 보이는데 get_vars(x, {:list type})이거나???
  #
  # defp get_vars(op, {:list, type}) when is_list(op), do: Enum.map(op, fn x -> get_vars(x, type) end)

  # Todo: Fix this!
  #   + 튜플 바깥쪽에 [ ... ]를 추가함!
  defp get_vars([ {:|, _, [operand1, operand2]} ], {:list, type}),
    do: [get_vars(operand1, type), get_vars(operand2, {:list, type})]

  defp get_vars(_, {:list, _}), do: {:error, "_ {:list, _} Parameters does not match type specification"}

  defp get_vars([], _), do: {:error, "[] Parameters does not match type specification"}

#  defp get_vars({:|, _, operandList}, type), do: {:error, ":| Parameters does not match type specification with " <> (operandList |> inspect) <> " , " <> (type |> inspect) }

  defp get_vars({:%{}, _, op}, {:map, {_, value_types}}), do: Enum.zip(op, value_types) |> Enum.map(fn {{_, value}, value_type} -> get_vars(value, value_type) end)

  defp get_vars({:%{}, _, _}, _), do: {:error, "Parameters does not match type specification"}

  defp get_vars(_, {:map, {_, _}}), do: {:error, "Parameters does not match type specification"}

  defp get_vars({:{}, _, ops}, {:tuple, type_list}), do: get_vars_tuple(ops, type_list)

  defp get_vars(ops, {:tuple, type_list}) when is_tuple(ops), do: get_vars_tuple(Tuple.to_list(ops), type_list)

  defp get_vars({:{}, _, _}, _), do: {:error, "Parameters does not match type specification"}

  defp get_vars(_, {:tuple, _}), do: {:error, "Parameters does not match type specification"}

  defp get_vars(value, type) when (type in [:string, :boolean, :integer, :float, :atom, :any]) do
    cond do
      type === :any or
      (is_boolean(value) and type === :boolean) or
      (is_bitstring(value) and type === :string) or
      (is_integer(value) and (type === :integer or type === :float)) or
      (is_float(value) and type === :float) or
      (is_atom(value) and type === :atom)
        -> []
      true -> {:error, "Parameters does not match type specification " <> (value |> inspect) <> " , " <> (type |> inspect)}
    end
  end

  defp get_vars(value, type), do: {:error, "Parameters does not match type specification " <> (value |> inspect) <> " , " <> (type |> inspect)}

  defp get_vars_tuple(ops, type_list) do
    if length(ops) === length(type_list),
      do: Enum.zip(ops, type_list) |> Enum.map(fn {var, type} -> get_vars(var, type) end),
      else: {:error, "The number of parameters in tuple does not match the number of types"}
  end
end
