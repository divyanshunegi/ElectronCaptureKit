import os from 'node:os';
import { debuglog } from 'node:util';
import path from 'node:path';
import url from 'node:url';
import { execa } from 'execa';
import { temporaryFile } from 'tempy';
import { assertMacOSVersionGreaterThanOrEqualTo } from 'macos-version';
import fileUrl from 'file-url';
import { fixPathForAsarUnpack } from 'electron-util/node';
import delay from 'delay';

const log = debuglog('capturekit');
const getRandomId = () => Math.random().toString(36).slice(2, 15);

const dirname_ = path.dirname(url.fileURLToPath(import.meta.url));
// Workaround for https://github.com/electron/electron/issues/9459
const BINARY = path.join(fixPathForAsarUnpack(dirname_), 'capturekit');

class Recorder {
    constructor() {
        assertMacOSVersionGreaterThanOrEqualTo('12.3');
        this.process = null;
    }

    async startRecording({
        fps = 30,
        showCursor = true,
        displayId = 1, // Assuming main display by default
    } = {}) {
        if (this.process) {
            throw new Error('Recording is already in progress. Call stopRecording() first.');
        }

        const config = JSON.stringify({
            fps,
            showCursor,
            displayId,
        });

        this.process = execa(BINARY, ['start', config]);

        return new Promise((resolve, reject) => {
            this.process.stdout.on('data', (data) => {
                const message = data.toString().trim();
                log(message);
                if (message.includes('Capture started.')) {
                    resolve();
                }
            });

            this.process.stderr.on('data', (data) => {
                log(`stderr: ${data}`);
            });

            this.process.on('error', (error) => {
                reject(error);
            });
        });
    }

    async stopRecording() {
        if (!this.process) {
            throw new Error('No recording in progress. Call startRecording() first.');
        }

        this.process.stdin.write('stop\n');

        return new Promise((resolve, reject) => {
            this.process.stdout.on('data', (data) => {
                const message = data.toString().trim();
                log(message);
                if (message.startsWith('Recording stopped. Output path:')) {
                    const outputPath = message.split(':')[1].trim();
                    this.process = null;
                    resolve(outputPath);
                }
            });

            this.process.on('error', (error) => {
                reject(error);
            });
        });
    }
}

export const recorder = new Recorder();

export const getAvailableDisplays = async () => {
    const { stdout } = await execa(BINARY, ['start', '{"fps": 30, "showCursor": true, "displayId": 1}']);
    const displays = stdout.match(/Available displays: (.*)/);
    if (displays && displays[1]) {
        return displays[1].split(', ').map(Number);
    }
    return [];
};