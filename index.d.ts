declare class CaptureKit {
    constructor();
    startRecording(options?: {
      fps?: number;
      showCursor?: boolean;
      displayId?: number;
    }): Promise<void>;
    stopRecording(): Promise<string>;
  }
  
  export = CaptureKit;