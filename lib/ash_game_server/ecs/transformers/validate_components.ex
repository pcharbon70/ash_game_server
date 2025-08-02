defmodule AshGameServer.ECS.Transformers.ValidateComponents do
  @moduledoc """
  Transformer that validates component definitions.
  
  Ensures that:
  - Component names are unique
  - Attribute names within components are unique
  - Attribute types are valid
  - Default values match attribute types
  """
  
  use Spark.Dsl.Transformer
  
  alias Spark.Dsl.Transformer
  
  @impl true
  def transform(dsl_state) do
    components = Transformer.get_entities(dsl_state, [:components])
    
    with :ok <- validate_unique_names(components),
         :ok <- validate_attributes(components) do
      {:ok, dsl_state}
    else
      {:error, error} ->
        {:error, dsl_state, error}
    end
  end
  
  defp validate_unique_names(components) do
    names = Enum.map(components, & &1.name)
    
    case names -- Enum.uniq(names) do
      [] ->
        :ok
        
      duplicates ->
        {:error,
         Spark.Error.DslError.exception(
           message: "Duplicate component names found: #{inspect(duplicates)}",
           path: [:components]
         )}
    end
  end
  
  defp validate_attributes(components) do
    Enum.reduce_while(components, :ok, fn component, :ok ->
      case validate_component_attributes(component) do
        :ok -> {:cont, :ok}
        error -> {:halt, error}
      end
    end)
  end
  
  defp validate_component_attributes(component) do
    with :ok <- validate_unique_attribute_names(component),
         :ok <- validate_attribute_types(component) do
      validate_default_values(component)
    end
  end
  
  defp validate_unique_attribute_names(component) do
    attr_names = Enum.map(component.attributes, & &1.name)
    
    case attr_names -- Enum.uniq(attr_names) do
      [] ->
        :ok
        
      duplicates ->
        {:error,
         Spark.Error.DslError.exception(
           message: "Duplicate attribute names in component #{component.name}: #{inspect(duplicates)}",
           path: [:components, component.name]
         )}
    end
  end
  
  defp validate_attribute_types(component) do
    valid_types = [:integer, :float, :string, :boolean, :atom, :map, :list, :uuid, :datetime]
    
    Enum.reduce_while(component.attributes, :ok, fn attr, :ok ->
      if attr.type in valid_types do
        {:cont, :ok}
      else
        {:halt,
         {:error,
          Spark.Error.DslError.exception(
            message: "Invalid attribute type #{inspect(attr.type)} for #{attr.name} in component #{component.name}",
            path: [:components, component.name, :attributes, attr.name]
          )}}
      end
    end)
  end
  
  defp validate_default_values(component) do
    Enum.reduce_while(component.attributes, :ok, fn attr, :ok ->
      if attr.default == nil or valid_default?(attr.type, attr.default) do
        {:cont, :ok}
      else
        {:halt,
         {:error,
          Spark.Error.DslError.exception(
            message: "Invalid default value for attribute #{attr.name} in component #{component.name}",
            path: [:components, component.name, :attributes, attr.name]
          )}}
      end
    end)
  end
  
  defp valid_default?(type, value) do
    validate_by_type_group(type, value)
  end
  
  defp validate_by_type_group(:integer, value), do: is_integer(value)
  defp validate_by_type_group(:float, value), do: is_number(value)
  defp validate_by_type_group(:string, value), do: is_binary(value)
  defp validate_by_type_group(:uuid, value), do: is_binary(value)
  defp validate_by_type_group(:boolean, value), do: is_boolean(value)
  defp validate_by_type_group(:atom, value), do: is_atom(value)
  defp validate_by_type_group(:map, value), do: is_map(value)
  defp validate_by_type_group(:list, value), do: is_list(value)
  defp validate_by_type_group(:datetime, value), do: match?(%DateTime{}, value)
  defp validate_by_type_group(_, _), do: false
end