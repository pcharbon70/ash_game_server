defmodule AshGameServer.Components.TransformTest do
  use ExUnit.Case, async: true
  
  alias AshGameServer.Components.Transform
  alias AshGameServer.Components.Transform.{Position, Rotation, Scale, Velocity}
  
  describe "Position component" do
    test "creates position at origin" do
      pos = Position.origin()
      assert pos.x == 0.0
      assert pos.y == 0.0
      assert pos.z == 0.0
    end
    
    test "creates position with coordinates" do
      pos = Position.new(10, 20, 30)
      assert pos.x == 10.0
      assert pos.y == 20.0
      assert pos.z == 30.0
    end
    
    test "calculates distance between positions" do
      p1 = Position.new(0, 0, 0)
      p2 = Position.new(3, 4, 0)
      
      assert Position.distance(p1, p2) == 5.0
    end
    
    test "adds positions" do
      p1 = Position.new(1, 2, 3)
      p2 = Position.new(4, 5, 6)
      result = Position.add(p1, p2)
      
      assert result.x == 5.0
      assert result.y == 7.0
      assert result.z == 9.0
    end
    
    test "validates position" do
      assert :ok = Position.validate(%Position{x: 1, y: 2, z: 3})
      assert {:error, _} = Position.validate(%Position{x: "invalid", y: 2, z: 3})
    end
    
    test "serializes and deserializes" do
      pos = Position.new(1.234, 5.678, 9.012)
      serialized = Position.serialize(pos)
      {:ok, deserialized} = Position.deserialize(serialized)
      
      assert_in_delta deserialized.x, pos.x, 0.01
      assert_in_delta deserialized.y, pos.y, 0.01
      assert_in_delta deserialized.z, pos.z, 0.01
    end
  end
  
  describe "Rotation component" do
    test "creates identity rotation" do
      rot = Rotation.identity()
      assert rot.pitch == 0.0
      assert rot.yaw == 0.0
      assert rot.roll == 0.0
    end
    
    test "creates rotation from degrees" do
      rot = Rotation.from_degrees(90, 180, 45)
      
      assert_in_delta rot.pitch, :math.pi() / 2, 0.01
      assert_in_delta rot.yaw, :math.pi(), 0.01
      assert_in_delta rot.roll, :math.pi() / 4, 0.01
    end
    
    test "gets forward vector" do
      rot = Rotation.identity()
      forward = Rotation.forward(rot)
      
      assert_in_delta forward.x, 0.0, 0.01
      assert_in_delta forward.y, 0.0, 0.01
      assert_in_delta forward.z, 1.0, 0.01
    end
    
    test "validates rotation" do
      assert :ok = Rotation.validate(%Rotation{pitch: 1, yaw: 2, roll: 3})
      assert {:error, _} = Rotation.validate(%Rotation{pitch: "invalid", yaw: 2, roll: 3})
    end
  end
  
  describe "Scale component" do
    test "creates uniform scale" do
      scale = Scale.uniform(2.0)
      assert scale.x == 2.0
      assert scale.y == 2.0
      assert scale.z == 2.0
    end
    
    test "creates identity scale" do
      scale = Scale.identity()
      assert scale.x == 1.0
      assert scale.y == 1.0
      assert scale.z == 1.0
    end
    
    test "multiplies scales" do
      s1 = Scale.new(2, 3, 4)
      s2 = Scale.new(5, 6, 7)
      result = Scale.multiply(s1, s2)
      
      assert result.x == 10.0
      assert result.y == 18.0
      assert result.z == 28.0
    end
    
    test "validates scale" do
      assert :ok = Scale.validate(%Scale{x: 1, y: 2, z: 3})
      assert {:error, _} = Scale.validate(%Scale{x: -1, y: 2, z: 3})
    end
    
    test "checks if scale is uniform" do
      assert Scale.uniform?(Scale.uniform(2.0))
      refute Scale.uniform?(Scale.new(1, 2, 3))
    end
  end
  
  describe "Velocity component" do
    test "creates zero velocity" do
      vel = Velocity.zero()
      assert vel.linear_x == 0.0
      assert vel.linear_y == 0.0
      assert vel.linear_z == 0.0
      assert vel.angular_x == 0.0
      assert vel.angular_y == 0.0
      assert vel.angular_z == 0.0
    end
    
    test "creates linear velocity" do
      vel = Velocity.linear(10, 20, 30)
      assert vel.linear_x == 10.0
      assert vel.linear_y == 20.0
      assert vel.linear_z == 30.0
    end
    
    test "calculates linear speed" do
      vel = Velocity.linear(3, 4, 0)
      assert Velocity.linear_speed(vel) == 5.0
    end
    
    test "applies damping" do
      vel = Velocity.linear(10, 10, 10)
      damped = Velocity.damp(vel, 0.1)
      
      assert damped.linear_x == 9.0
      assert damped.linear_y == 9.0
      assert damped.linear_z == 9.0
    end
    
    test "checks if stopped" do
      assert Velocity.stopped?(Velocity.zero())
      refute Velocity.stopped?(Velocity.linear(1, 0, 0))
    end
    
    test "validates velocity" do
      assert :ok = Velocity.validate(%Velocity{})
      
      invalid = %Velocity{linear_x: "invalid"}
      assert {:error, _} = Velocity.validate(invalid)
    end
  end
  
  describe "Transform module" do
    test "creates complete transform" do
      transform = Transform.new()
      
      assert transform.position == Position.origin()
      assert transform.rotation == Rotation.identity()
      assert transform.scale == Scale.identity()
      assert transform.velocity == Velocity.zero()
    end
    
    test "applies velocity over time" do
      transform = Transform.new(
        position: Position.new(0, 0, 0),
        velocity: Velocity.linear(10, 5, 0)
      )
      
      updated = Transform.apply_velocity(transform, 2.0)
      
      assert updated.position.x == 20.0
      assert updated.position.y == 10.0
      assert updated.position.z == 0.0
    end
    
    test "checks if transform is modified" do
      refute Transform.modified?(Transform.new())
      
      modified = Transform.new(position: Position.new(1, 0, 0))
      assert Transform.modified?(modified)
    end
    
    test "interpolates between transforms" do
      t1 = Transform.new(position: Position.new(0, 0, 0))
      t2 = Transform.new(position: Position.new(10, 10, 10))
      
      result = Transform.lerp(t1, t2, 0.5)
      
      assert result.position.x == 5.0
      assert result.position.y == 5.0
      assert result.position.z == 5.0
    end
  end
end