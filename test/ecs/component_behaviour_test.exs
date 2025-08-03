defmodule AshGameServer.ECS.ComponentBehaviourTest do
  use ExUnit.Case, async: true

  alias AshGameServer.ECS.ComponentBehaviour

  defmodule TestComponent do
    @behaviour ComponentBehaviour

    @impl ComponentBehaviour
    def metadata do
      %{
        name: :test_component,
        version: 1,
        schema: [
          name: :string,
          value: :integer,
          active: :boolean
        ],
        indexes: [:name, :active],
        persistent: true,
        validations: [:validate_name],
        description: "A test component for unit testing"
      }
    end

    @impl ComponentBehaviour
    def validate(data) do
      if is_binary(Map.get(data, :name)) and String.length(Map.get(data, :name, "")) > 0 do
        :ok
      else
        {:error, :invalid_name}
      end
    end
  end

  defmodule InvalidComponent do
    # Missing required callbacks
  end

  describe "component behaviour" do
    test "defines required callbacks" do
      callbacks = ComponentBehaviour.behaviour_info(:callbacks)
      
      assert {:metadata, 0} in callbacks
      assert {:validate, 1} in callbacks
    end

    test "valid component implements all callbacks" do
      assert function_exported?(TestComponent, :metadata, 0)
      assert function_exported?(TestComponent, :validate, 1)
    end

    test "metadata returns required fields" do
      metadata = TestComponent.metadata()
      
      assert Map.has_key?(metadata, :name)
      assert Map.has_key?(metadata, :version)
      assert Map.has_key?(metadata, :schema)
      assert Map.has_key?(metadata, :indexes)
      assert Map.has_key?(metadata, :persistent)
      assert Map.has_key?(metadata, :validations)
      assert Map.has_key?(metadata, :description)
    end

    test "validate function works correctly" do
      valid_data = %{name: "test", value: 42, active: true}
      invalid_data = %{name: "", value: 42, active: true}

      assert TestComponent.validate(valid_data) == :ok
      assert TestComponent.validate(invalid_data) == {:error, :invalid_name}
    end

    test "metadata contains expected values" do
      metadata = TestComponent.metadata()
      
      assert metadata.name == :test_component
      assert metadata.version == 1
      assert metadata.indexes == [:name, :active]
      assert metadata.persistent == true
    end
  end
end