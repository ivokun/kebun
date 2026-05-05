export interface CheckpointStore {
    save(id: string, data: {
        elements: any[];
    }): Promise<void>;
    load(id: string): Promise<{
        elements: any[];
    } | null>;
}
export declare class FileCheckpointStore implements CheckpointStore {
    private dir;
    constructor();
    save(id: string, data: {
        elements: any[];
    }): Promise<void>;
    load(id: string): Promise<{
        elements: any[];
    } | null>;
    /** Remove oldest checkpoints when count exceeds the limit. */
    private pruneOldCheckpoints;
}
export declare class MemoryCheckpointStore implements CheckpointStore {
    save(id: string, data: {
        elements: any[];
    }): Promise<void>;
    load(id: string): Promise<{
        elements: any[];
    } | null>;
}
export declare class RedisCheckpointStore implements CheckpointStore {
    private redis;
    private getRedis;
    save(id: string, data: {
        elements: any[];
    }): Promise<void>;
    load(id: string): Promise<{
        elements: any[];
    } | null>;
}
export declare function createVercelStore(): CheckpointStore;
