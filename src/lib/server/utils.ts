// import { Result as FunctionalResult } from '@badrap/result';

// export async function sh(
// 	cmd: string
// ): Promise<FunctionalResult<{ stdout: string; stderr: string }, Error>> {
// 	return new Promise(function (_resolve, _reject) {
// 		// exec(cmd, (err, stdout, stderr) => {
// 		// 	if (err) {
// 		// 		reject(FunctionalResult.err(err));
// 		// 	} else {
// 		// 		resolve(FunctionalResult.ok({ stdout, stderr }));
// 		// 	}
// 		// });
// 	});
// }

// export const powershell = (cmd: string) => sh(`powershell ${cmd}`);

export default {};
