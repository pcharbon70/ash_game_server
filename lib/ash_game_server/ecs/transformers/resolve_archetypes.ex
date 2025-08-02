defmodule AshGameServer.ECS.Transformers.ResolveArchetypes do
  @moduledoc """
  Transformer that resolves archetype inheritance.
  
  Merges component definitions from parent archetypes to create
  complete component lists for each archetype and entity.
  """
  
  use Spark.Dsl.Transformer
  
  alias Spark.Dsl.Transformer
  
  @impl true
  def transform(dsl_state) do
    entities = Transformer.get_entities(dsl_state, [:entities])
    
    archetypes = 
      entities
      |> Enum.filter(&(&1.__struct__ == AshGameServer.ECS.Archetype))
      |> build_archetype_map()
    
    # Resolve archetype inheritance
    resolved_archetypes = resolve_inheritance(archetypes)
    
    # Update archetypes with resolved components
    dsl_state = 
      Enum.reduce(resolved_archetypes, dsl_state, fn {name, archetype}, state ->
        Transformer.replace_entity(state, [:entities], archetype, & &1.name == name)
      end)
    
    # Resolve entity templates
    templates = Enum.filter(entities, &(&1.__struct__ == AshGameServer.ECS.EntityTemplate))
    
    dsl_state = 
      Enum.reduce(templates, dsl_state, fn template, state ->
        resolved_template = resolve_template(template, resolved_archetypes)
        Transformer.replace_entity(state, [:entities], resolved_template, & &1.name == template.name)
      end)
    
    {:ok, dsl_state}
  end
  
  defp build_archetype_map(archetypes) do
    Map.new(archetypes, &{&1.name, &1})
  end
  
  defp resolve_inheritance(archetypes) do
    Enum.reduce(archetypes, %{}, fn {name, archetype}, resolved ->
      Map.put(resolved, name, resolve_archetype(archetype, archetypes, resolved))
    end)
  end
  
  defp resolve_archetype(archetype, all_archetypes, resolved) do
    if archetype.extends do
      parent = 
        case Map.get(resolved, archetype.extends) do
          nil ->
            parent_archetype = Map.get(all_archetypes, archetype.extends)
            resolve_archetype(parent_archetype, all_archetypes, resolved)
          
          resolved_parent ->
            resolved_parent
        end
      
      merge_archetypes(parent, archetype)
    else
      archetype
    end
  end
  
  defp merge_archetypes(parent, child) do
    # Merge components, with child components overriding parent ones
    merged_components = merge_components(parent.components, child.components)
    
    %{child | components: merged_components}
  end
  
  defp merge_components(parent_components, child_components) do
    parent_map = Map.new(parent_components, &{&1.name, &1})
    child_map = Map.new(child_components, &{&1.name, &1})
    
    merged_map = Map.merge(parent_map, child_map)
    Map.values(merged_map)
  end
  
  defp resolve_template(template, archetypes) do
    if template.from_archetype do
      archetype = Map.get(archetypes, template.from_archetype)
      
      if archetype do
        merged_components = merge_components(archetype.components, template.components)
        %{template | components: merged_components}
      else
        template
      end
    else
      template
    end
  end
end