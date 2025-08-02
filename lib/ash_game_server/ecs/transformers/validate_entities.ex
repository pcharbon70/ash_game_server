defmodule AshGameServer.ECS.Transformers.ValidateEntities do
  @moduledoc """
  Transformer that validates entity and archetype definitions.
  
  Ensures that:
  - Entity and archetype names are unique
  - Component references are valid
  - Archetype inheritance is valid
  """
  
  use Spark.Dsl.Transformer
  
  alias Spark.Dsl.Transformer
  
  @impl true
  def transform(dsl_state) do
    entities = Transformer.get_entities(dsl_state, [:entities])
    components = Transformer.get_entities(dsl_state, [:components])
    
    archetypes = Enum.filter(entities, &(&1.__struct__ == AshGameServer.ECS.Archetype))
    templates = Enum.filter(entities, &(&1.__struct__ == AshGameServer.ECS.EntityTemplate))
    
    with :ok <- validate_unique_names(archetypes, templates),
         :ok <- validate_component_refs(entities, components),
         :ok <- validate_archetype_inheritance(archetypes),
         :ok <- validate_template_archetypes(templates, archetypes) do
      {:ok, dsl_state}
    else
      {:error, error} ->
        {:error, dsl_state, error}
    end
  end
  
  defp validate_unique_names(archetypes, templates) do
    all_names = 
      Enum.map(archetypes, & &1.name) ++ 
      Enum.map(templates, & &1.name)
    
    case all_names -- Enum.uniq(all_names) do
      [] ->
        :ok
        
      duplicates ->
        {:error,
         Spark.Error.DslError.exception(
           message: "Duplicate entity/archetype names found: #{inspect(duplicates)}",
           path: [:entities]
         )}
    end
  end
  
  defp validate_component_refs(entities, components) do
    component_names = MapSet.new(Enum.map(components, & &1.name))
    
    Enum.reduce_while(entities, :ok, fn entity, :ok ->
      invalid_refs = 
        entity.components
        |> Enum.map(& &1.name)
        |> Enum.reject(&MapSet.member?(component_names, &1))
      
      if invalid_refs == [] do
        {:cont, :ok}
      else
        {:halt,
         {:error,
          Spark.Error.DslError.exception(
            message: "Entity/archetype #{entity.name} references undefined components: #{inspect(invalid_refs)}",
            path: [:entities, entity.name]
          )}}
      end
    end)
  end
  
  defp validate_archetype_inheritance(archetypes) do
    archetype_names = MapSet.new(Enum.map(archetypes, & &1.name))
    
    Enum.reduce_while(archetypes, :ok, fn archetype, :ok ->
      if archetype.extends == nil or MapSet.member?(archetype_names, archetype.extends) do
        {:cont, :ok}
      else
        {:halt,
         {:error,
          Spark.Error.DslError.exception(
            message: "Archetype #{archetype.name} extends undefined archetype: #{archetype.extends}",
            path: [:entities, archetype.name]
          )}}
      end
    end)
  end
  
  defp validate_template_archetypes(templates, archetypes) do
    archetype_names = MapSet.new(Enum.map(archetypes, & &1.name))
    
    Enum.reduce_while(templates, :ok, fn template, :ok ->
      if template.from_archetype == nil or MapSet.member?(archetype_names, template.from_archetype) do
        {:cont, :ok}
      else
        {:halt,
         {:error,
          Spark.Error.DslError.exception(
            message: "Entity #{template.name} references undefined archetype: #{template.from_archetype}",
            path: [:entities, template.name]
          )}}
      end
    end)
  end
end