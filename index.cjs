'use strict';

const path = require('path');
const execa = require('execa');

const BINARY = path.join(__dirname, 'capturekit');

class Recorder {
    constructor() {
        this.process = null;
    }

    async startRecording(config = {}) {
        if (this.process) {
            throw new Error('Recording is already in progress');
        }
        const configJSON = JSON.stringify(config);        
        this.process = execa(BINARY, [configJSON]);
        this.process.stdout.on('data', (data) => {
            console.log(`capturekit: ${data.toString().trim()}`);
        });
        this.process.stderr.on('data', (data) => {
            console.error(`capturekit error: ${data.toString().trim()}`);
        });
        // Wait for the "Recording started" message
        await new Promise((resolve, reject) => {
            this.process.stdout.on('data', (data) => {
                if (data.toString().includes('Recording started')) {
                    resolve();
                }
            });
            this.process.on('error', reject);
        });
    }

    async stopRecording() {
        if (!this.process) {
            throw new Error('No recording in progress');
        }
    
        return new Promise((resolve, reject) => {
            let output = '';
    
            // Collect all stdout data
            this.process.stdout.on('data', (data) => {
                output += data.toString();
                console.log(`capturekit: ${data.toString().trim()}`);
            });
    
            // Send the 'stop' command
            this.process.stdin.write('stop\n');
    
            this.process.on('close', (code) => {
                this.process = null;
                if (code !== 0) {
                    reject(new Error(`Process exited with code ${code}`));
                    return;
                }
    
                // Extract the output path from the collected stdout
                const match = output.match(/Output path: (.+)/);
                if (match) {
                    resolve(match[1].trim());
                } else {
                    reject(new Error('Could not find output path in process output'));
                }
            });
    
            this.process.on('error', reject);
        });
    }
}

const recorder = new Recorder();

module.exports = { recorder };