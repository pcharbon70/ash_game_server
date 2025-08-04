defmodule AshGameServer.Systems.SystemAnalyticsTest do
  use ExUnit.Case, async: false
  
  alias AshGameServer.Systems.SystemAnalytics
  
  setup do
    {:ok, pid} = SystemAnalytics.start_link(telemetry_enabled: false)
    
    on_exit(fn ->
      if Process.alive?(pid) do
        GenServer.stop(pid)
      end
    end)
    
    {:ok, analytics: pid}
  end
  
  describe "record_execution/4" do
    test "records successful execution metrics" do
      SystemAnalytics.record_execution(:test_system, 10.5, 100, true)
      
      {:ok, metrics} = SystemAnalytics.get_system_metrics(:test_system)
      
      assert metrics.average_execution_time == 10.5
      assert metrics.error_count == 0
      assert metrics.average_entity_count == 100.0
    end
    
    test "records failed execution metrics" do
      SystemAnalytics.record_execution(:test_system, 15.0, 50, false)
      
      {:ok, metrics} = SystemAnalytics.get_system_metrics(:test_system)
      
      assert metrics.error_count == 1
    end
    
    test "calculates running averages" do
      SystemAnalytics.record_execution(:test_system, 10.0, 100, true)
      SystemAnalytics.record_execution(:test_system, 20.0, 150, true)
      SystemAnalytics.record_execution(:test_system, 15.0, 125, true)
      
      {:ok, metrics} = SystemAnalytics.get_system_metrics(:test_system)
      
      assert metrics.average_execution_time == 15.0
      assert metrics.average_entity_count == 125.0
      assert metrics.max_execution_time == 20.0
      assert metrics.min_execution_time == 10.0
    end
  end
  
  describe "get_all_metrics/0" do
    test "returns metrics for all systems" do
      SystemAnalytics.record_execution(:system_a, 10.0, 100, true)
      SystemAnalytics.record_execution(:system_b, 20.0, 200, true)
      
      {:ok, all_metrics} = SystemAnalytics.get_all_metrics()
      
      assert Map.has_key?(all_metrics, :system_a)
      assert Map.has_key?(all_metrics, :system_b)
      
      assert all_metrics.system_a.average_execution_time == 10.0
      assert all_metrics.system_b.average_execution_time == 20.0
    end
  end
  
  describe "get_summary/0" do
    test "generates performance summary" do
      SystemAnalytics.record_execution(:fast_system, 5.0, 50, true)
      SystemAnalytics.record_execution(:slow_system, 50.0, 500, true)
      SystemAnalytics.record_execution(:error_system, 10.0, 100, false)
      
      {:ok, summary} = SystemAnalytics.get_summary()
      
      assert summary.total_systems == 3
      assert summary.total_errors == 1
      assert summary.systems_with_errors == 1
      assert summary.slowest_system == :slow_system
      assert summary.fastest_system == :fast_system
    end
    
    test "handles empty metrics" do
      {:ok, summary} = SystemAnalytics.get_summary()
      
      assert summary.total_systems == 0
      assert summary.total_errors == 0
      assert summary.slowest_system == nil
      assert summary.fastest_system == nil
    end
  end
  
  describe "reset_metrics/1" do
    test "resets metrics for specific system" do
      SystemAnalytics.record_execution(:test_system, 10.0, 100, true)
      
      assert :ok = SystemAnalytics.reset_metrics(:test_system)
      
      {:ok, metrics} = SystemAnalytics.get_system_metrics(:test_system)
      assert metrics.average_execution_time == 0.0
      assert metrics.error_count == 0
    end
    
    test "resets all metrics" do
      SystemAnalytics.record_execution(:system_a, 10.0, 100, true)
      SystemAnalytics.record_execution(:system_b, 20.0, 200, true)
      
      assert :ok = SystemAnalytics.reset_metrics(:all)
      
      {:ok, all_metrics} = SystemAnalytics.get_all_metrics()
      assert all_metrics == %{}
    end
  end
  
  describe "anomaly detection" do
    test "detects performance anomalies" do
      # Establish baseline
      for _ <- 1..20 do
        SystemAnalytics.record_execution(:test_system, 10.0 + :rand.uniform(), 100, true)
      end
      
      # Record anomaly
      SystemAnalytics.record_execution(:test_system, 100.0, 100, true)
      
      {:ok, anomalies} = SystemAnalytics.check_anomalies()
      
      # Should detect the anomaly
      assert :test_system in anomalies
    end
    
    test "no false positives for consistent performance" do
      # All similar execution times
      for _ <- 1..20 do
        SystemAnalytics.record_execution(:consistent_system, 10.0, 100, true)
      end
      
      {:ok, anomalies} = SystemAnalytics.check_anomalies()
      
      assert :consistent_system not in anomalies
    end
  end
  
  describe "telemetry integration" do
    test "enables and disables telemetry" do
      assert :ok = SystemAnalytics.set_telemetry(true)
      assert :ok = SystemAnalytics.set_telemetry(false)
    end
  end
  
  describe "export_metrics/1" do
    test "exports metrics to file" do
      SystemAnalytics.record_execution(:test_system, 10.0, 100, true)
      
      filepath = "/tmp/test_metrics_#{System.unique_integer([:positive])}.json"
      
      assert {:ok, ^filepath} = SystemAnalytics.export_metrics(filepath)
      assert File.exists?(filepath)
      
      # Cleanup
      File.rm!(filepath)
    end
  end
end