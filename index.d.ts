declare class Recorder {
    startRecording(config?: any): Promise<void>;
    stopRecording(): Promise<string>;
}

export const recorder: Recorder;

export as namespace capturekit;