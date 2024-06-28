import fs from 'fs';
import { recorder } from './index.js';
import readline from 'readline';

const rl = readline.createInterface({
    input: process.stdin,
    output: process.stdout
});

async function main() {
    try {
        console.log('Starting recording...');
        
        recorder.startRecording({
            fps: 30,
            showCursor: true,
            displayId: 3 // Use the first available display
        });

        console.log('Recording started. Type "stop" and press Enter to stop recording, or wait for 30 seconds.');

        // Set up a promise that resolves when the user types "stop"
       
        setTimeout(async () => {
            console.log('Stopping recording...');
            const path = await recorder.stopRecording();
            console.log('Recording PATH:', path);
        }, 5000);

    } catch (error) {
        console.error('An error occurred:', error);
    } finally {
        rl.close();
    }
}

main().catch(error => {
    console.error('Unhandled error in main:', error);
    rl.close();
});