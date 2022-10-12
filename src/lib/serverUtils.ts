import { exec } from 'child_process';
import { Result } from '@badrap/result';

export async function sh(cmd: string): Promise<Result<{ stdout: string; stderr: string }, Error>> {
	return new Promise(function (resolve, reject) {
		exec(cmd, (err, stdout, stderr) => {
			if (err) {
				reject(Result.err(err));
			} else {
				resolve(Result.ok({ stdout, stderr }));
			}
		});
	});
}

export const powershell = (cmd: string) => sh(`powershell ${cmd}`);
