# Terminal Spatial Engine (TSE) - Development Epics

## Epic 1: Spatial Memory & ECS Architecture
**Objective:** Define the high-performance memory model and entity management.

### Technical Requirements:
1.  **Arena Management:** Implement `tse.memory.Arena` for stable, high-speed allocation of components.
2.  **Entity Registry:** Create a `tse.ecs.Registry` struct capable of handling up to 100,000 entities. Use an `Id` generation pattern that reuses freed indices.
3.  **Component Storage:** Implement sparse-set storage for `Position`, `Velocity`, and `SpatialIndex` components to maintain CPU cache locality.
4.  **Spatial Indexing:** Add a basic QuadTree implementation for efficient spatial queries within the ECS.

### Success Criteria:
- Zero manual `free()` calls in the hot path.
- Registry lookup O(1) performance.
- Ability to toggle QuadTree optimization for dynamic vs. static entities.
