
# ECS Architecture Using Jido, Ash, and Spark for Multiplayer Server

## Overview 
The **Entity-Component-System (ECS)** is a game architecture pattern that separates game objects into *entities* (unique IDs), *components* (data associated with an entity), and *systems* (logic that operates on entities with certain components). This design promotes flexibility and performance by allowing behavior to emerge from combinations of components rather than deep inheritance hierarchies. In this architecture, we combine ECS with the **Ash Framework** (for domain modeling and persistence) and the **Jido agentic framework** (for concurrent, autonomous behavior) to create a scalable, server-side game system. The goal is a **multi-player** capable server that keeps game state in-memory for speed, persists state and events for reliability, and uses an agent-based approach for game logic and AI.

**Key concepts include:** (1) Entities defined abstractly (just an ID with no rigid class structure), (2) Components as modular data units that can be attached to entities (e.g. position, velocity, health), (3) Systems as the logic that processes entities having certain components (e.g. a Movement system updates all entities with position+velocity each tick), (4) Agents (via Jido) to give systems or entities autonomous, concurrent behaviors, and (5) Multi-layer persistence: in-memory state for fast access, periodic database snapshots for durability, and an event log for recovery and audit. We remain abstract (not tied to a specific game genre) to ensure the design is broadly applicable to different multiplayer games.

## Entity and Component Modeling with Ash 
**Entities** in ECS are simple and lightweight – typically just a unique identifier without inherent data. All game state is expressed through components attached to these entity IDs. In our design, we leverage the Ash Framework to define the schema of each component type and to persist their data. Each **Component** (such as `Position`, `Health`, `Velocity`, etc.) can be defined as an Ash **Resource** with fields for the entity ID and the relevant attributes (for example, a `Position` component resource might have fields: `entity_id`, `x`, `y`). Ash resources use Ecto under the hood for database storage, so defining components as resources allows automatic generation of database tables and queries for persistence. 

To streamline defining new game-specific components, we would create a **Domain-Specific Language (DSL)** using Ash’s DSL tools (the Spark library). *Spark* is a toolkit for building DSLs in Elixir, and in fact *“powers all of the DSLs in Ash Framework”*. Using Spark, we can allow game developers to declare components in a concise way, which our framework will expand into Ash resource modules and any supporting code. For example, a pseudo-DSL might allow:

```elixir
component :Position do
  attribute :x, :integer
  attribute :y, :integer
end
```

Behind the scenes, this would use Spark to generate an Ash resource (with `x` and `y` fields, and an `entity_id` foreign key) as well as create an ETS table for `Position` components at runtime. Spark makes it easy to build such a DSL with built-in documentation and extension support, so game teams can define new components or even higher-level gameplay constructs without writing low-level boilerplate.

### Active State Storage
In a fast-paced game server, component data will be read and written many times per second, so we maintain the *active state* in-memory. We use **Erlang Term Storage (ETS)** for this, as it allows storing large amounts of data with constant-time lookups and updates. Concretely, the system would create an ETS table for each component type to map `entity_id` -> component data. For example, a `Color` component table might let us do `Color.get_one(entity_id)` to retrieve that entity’s color, or `Color.update(entity_id, new_color)` to change it. Storing each component type in its own ETS table follows the ECS principle of grouping by component, which improves cache locality and query speed. 

**Ash Integration:** While ETS holds the live state, Ash provides the *schema and persistence logic*. The Ash definitions of components ensure we have a single source of truth for data structure. We can periodically persist the contents of these ETS tables to the database through Ash – effectively taking snapshots. 

## System Logic as Jido Agents 
In a traditional ECS, **systems** are usually functions or objects that run each tick and iterate over relevant entities. A key challenge is ensuring systems don’t conflict when accessing data; ECSx (an Elixir ECS framework) solves this by running all system updates in a single GenServer loop, serializing them each tick to avoid race conditions. However, running all logic on one process can become a bottleneck on multi-core servers.

Our architecture takes an **agentic approach using Jido**, allowing more concurrency and flexibility. Jido is an Elixir framework for building autonomous agents that can plan and execute actions in a distributed environment. Instead of one monolithic game loop, we break the game logic into many small *agents* (processes) that handle different aspects of the simulation. This aligns with the BEAM’s ability to run thousands of lightweight processes concurrently, each isolated and fault-tolerant. 

### Entity Agents vs System Agents
There are a couple of ways to map ECS to agents:
- *Entity-centric:* Each dynamic entity (e.g. a player or NPC) is represented by its own Jido Agent process. This agent holds the entity’s components or has quick access to them, and is responsible for updating its state in response to events. 
- *System-centric:* Alternatively, we could assign an agent per *system* (per logic type) rather than per entity. For example, a dedicated **Physics agent** could handle all collision detection in the world, or a **Weather agent** could simulate global weather effects. 

In practice, the **entity-centric (agent per entity)** model pairs well with ECS storage. Each entity agent can immediately reflect changes in the in-memory component store (ETS) as it updates its state.

## Domain-Specific Language for Game Definitions (Spark) 
To make this architecture developer-friendly, we employ a DSL (Domain-Specific Language) powered by Ash’s **Spark** library for declaring game components, entities, and even system behaviors. Spark allows us to create **declarative configuration** that is then expanded into Elixir code and Ash definitions. By using a DSL, game developers and designers can define gameplay elements at a high level, without needing to know all the underlying OTP or Ash details. 

## Multi-Layer Persistence and State Management 
To support a **persistent, recoverable game world**, we employ three layers of state storage, each serving a specific purpose:

- **In-Memory State (ETS – Active State):** The primary game state lives in-memory for rapid access during gameplay.
- **Persistent Snapshots (Postgres – Durable State):** To avoid losing progress, the system takes periodic **snapshots** of the game state and stores them in a Postgres database.
- **Event Store (Append-Only Event Log for Recovery):** The third layer is an **Event Store** that records every significant change or input as an *event*. 

## Scalability and Multi-Player Considerations 
Designing for multi-player at scale means handling many concurrent players, NPCs, and interactions smoothly. The chosen architecture provides several advantages for scalability:
- **Concurrent Actors:** By using Jido and the BEAM’s actor model, we can run thousands of agents in parallel.
- **Consistency and Conflict Handling:** Our approach ensures **data consistency** by design: each entity’s state is owned and managed by a single process.
- **Scalable Persistence:** With many players, the volume of events and state updates can be huge. We should ensure the persistence layer can keep up.
- **Networking and Multi-player Sessions:** Each connected player could have a **session process** (like a Phoenix Channel process or a custom socket handler).

## Conclusion 
We have outlined a conceptual architecture for a scalable multiplayer game server that merges the ECS pattern with the strengths of the Ash framework and the Jido agent system. In summary, **Ash** is used to model and persist the game’s data (components, entities, events) in a declarative way, benefiting from its DSL and extension capabilities to enforce rules and automate persistence. **ECS** provides the high-performance, flexible way to structure game state and logic. **Jido** infuses the design with an *agentic*, concurrent execution model – turning systems and entities into intelligent agents that plan and act autonomously. The multi-layer storage (memory, database snapshots, event log) ensures that despite the volatility of a fast simulation, we don’t lose data and can recover from failures or even rewind history if needed.

This architecture remains abstract and extensible: one could tailor the set of components, the agent behaviors, or the snapshot frequency based on the game’s needs. Because we used Spark DSL to define these concepts, adding a new feature (like a new component type or a new system agent) is a matter of configuration that the framework handles, rather than writing low-level plumbing each time.

## Sources:
- DockYard (2023), *“ECSx: A New Approach to Game Development in Elixir”* – Explanation of ECS and ETS for fast component storage.
- AppUnite (2025), *“Integrating Generative AI into Elixir… using the Jido agentic framework”* – Describes Jido’s purpose as a toolkit for autonomous agents in distributed Elixir.
- Ash Framework & Spark – The Ash project’s DSL-building library, Spark, *“powers all of the DSLs in Ash”* and enables custom DSLs for defining components and game logic declaratively.

