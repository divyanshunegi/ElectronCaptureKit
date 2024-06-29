import { recorder } from './index.js';
import readline from 'node:readline';

const rl = readline.createInterface({
    input: process.stdin,
    output: process.stdout
});

async function main() {
    try {
        console.log('Starting recording...');
        
        await recorder.startRecording({
            fps: 30,
            showCursor: true,
            displayId: 3 // Use the first available display
        });

        console.log('Recording started. Waiting for 5 seconds before stopping...');

        setTimeout(async () => {
            console.log('Stopping recording...');
            try {
                const path = await recorder.stopRecording();
                console.log('Recording PATH:', path);
            } catch (error) {
                console.error('Error stopping recording:', error);
            } finally {
                rl.close();
            }
        }, 5000);

    } catch (error) {
        console.error('An error occurred:', error);
        rl.close();
    }
}

main().catch(error => {
    console.error('Unhandled error in main:', error);
    rl.close();
});