# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Commands

### Development
- `mix deps.get` - Install project dependencies
- `mix compile` - Compile the project
- `mix test` - Run all tests
- `mix format` - Format code according to .formatter.exs

### Testing
- `mix test` - Run all tests
- `mix test test/path/to/test.exs` - Run specific test file
- `mix test test/path/to/test.exs:LINE` - Run specific test at line number

## Architecture

This is an Ash framework-based game server extension implementing a hybrid ETS/PostgreSQL data layer with ECS (Entity Component System) architecture. Based on the system design in `planning/system_design.md`, the key architectural components are:

### Data Layer (Gaming.DataLayer.Hybrid)
- Uses ETS for hot storage of active game state
- PostgreSQL for persistent snapshots and checkpoints
- Event sourcing for recovery and replay
- Configurable checkpoint strategies (incremental, full, hybrid)

### ECS Integration
- Components defined as Ash attributes via DSL extensions
- Systems implemented as Ash changes and actions
- Cross-resource system coordination through domain-level extensions

### Key Extension Points
1. **Gaming.Extensions.ECS** - Resource-level ECS functionality
2. **Gaming.Extensions.GameWorld** - Domain-level world management
3. **Gaming.Extensions.GameEngine** - Master game configuration

### Resource Structure
- Player entities with position, velocity, health, inventory components
- Match resources managing game sessions and world state
- State machines for entity lifecycle management
- Checkpoint/recovery actions for resilience

The architecture leverages Ash's declarative patterns while maintaining high performance through ETS-based hot paths and sophisticated recovery mechanisms.