defmodule AshGameServer.ECS.ComponentRegistryTest do
  use ExUnit.Case, async: false

  alias AshGameServer.ECS.{ComponentRegistry, ComponentBehaviour}

  defmodule TestComponent do
    @behaviour ComponentBehaviour

    @impl ComponentBehaviour
    def metadata do
      %{
        name: :registry_test_component,
        version: 1,
        schema: [name: :string, level: :integer],
        indexes: [:name],
        persistent: true,
        validations: [],
        description: "Test component for registry"
      }
    end

    @impl ComponentBehaviour
    def validate(data) do
      if is_map(data) and Map.has_key?(data, :name) do
        :ok
      else
        {:error, :missing_name}
      end
    end
  end

  defmodule AnotherTestComponent do
    @behaviour ComponentBehaviour

    @impl ComponentBehaviour
    def metadata do
      %{
        name: :another_test_component,
        version: 2,
        schema: [health: :integer],
        indexes: [],
        persistent: false,
        validations: [],
        description: "Another test component"
      }
    end

    @impl ComponentBehaviour
    def validate(_data), do: :ok
  end

  setup do
    start_supervised!(ComponentRegistry)
    :ok
  end

  describe "component registration" do
    test "registers valid component successfully" do
      assert ComponentRegistry.register_component(TestComponent) == :ok
    end

    test "can retrieve registered component" do
      ComponentRegistry.register_component(TestComponent)
      
      assert {:ok, metadata} = ComponentRegistry.get_component(:registry_test_component)
      assert metadata.name == :registry_test_component
      assert metadata.version == 1
      assert metadata.module == TestComponent
    end

    test "returns error for non-existent component" do
      assert ComponentRegistry.get_component(:non_existent) == {:error, :not_found}
    end

    test "lists all registered components" do
      ComponentRegistry.register_component(TestComponent)
      ComponentRegistry.register_component(AnotherTestComponent)
      
      components = ComponentRegistry.list_components()
      assert length(components) == 2
      
      names = Enum.map(components, & &1.name)
      assert :registry_test_component in names
      assert :another_test_component in names
    end
  end

  describe "component search" do
    setup do
      ComponentRegistry.register_component(TestComponent)
      ComponentRegistry.register_component(AnotherTestComponent)
      :ok
    end

    test "finds components by criteria" do
      results = ComponentRegistry.find_components(persistent: true)
      assert length(results) == 1
      assert List.first(results).name == :registry_test_component
    end

    test "finds components by version" do
      results = ComponentRegistry.find_components(version: 2)
      assert length(results) == 1
      assert List.first(results).name == :another_test_component
    end

    test "returns empty list for no matches" do
      results = ComponentRegistry.find_components(version: 999)
      assert results == []
    end
  end

  describe "component validation" do
    setup do
      ComponentRegistry.register_component(TestComponent)
      :ok
    end

    test "validates component data successfully" do
      valid_data = %{name: "test", level: 5}
      assert ComponentRegistry.validate_component(:registry_test_component, valid_data) == :ok
    end

    test "returns validation error for invalid data" do
      invalid_data = %{level: 5}  # missing name
      assert ComponentRegistry.validate_component(:registry_test_component, invalid_data) == {:error, :missing_name}
    end

    test "returns error for non-existent component" do
      data = %{name: "test"}
      assert ComponentRegistry.validate_component(:non_existent, data) == {:error, :not_found}
    end
  end

  describe "version management" do
    setup do
      ComponentRegistry.register_component(TestComponent)
      ComponentRegistry.register_component(AnotherTestComponent)
      :ok
    end

    test "gets component version" do
      assert {:ok, 1} = ComponentRegistry.get_version(:registry_test_component)
      assert {:ok, 2} = ComponentRegistry.get_version(:another_test_component)
    end

    test "returns error for non-existent component version" do
      assert ComponentRegistry.get_version(:non_existent) == {:error, :not_found}
    end

    test "can_migrate? returns false by default" do
      # Since our test components don't implement migrate/3
      assert ComponentRegistry.can_migrate?(:registry_test_component, 0, 1) == false
    end

    test "migrate_component returns data unchanged for same version" do
      data = %{name: "test", level: 5}
      assert {:ok, ^data} = ComponentRegistry.migrate_component(:registry_test_component, data, 1)
    end
  end

  describe "error handling" do
    test "handles invalid module registration gracefully" do
      defmodule InvalidModule do
        # No behaviour implementation
      end

      result = ComponentRegistry.register_component(InvalidModule)
      assert {:error, :invalid_component} = result
    end
  end
end