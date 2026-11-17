// Formats a whole, non-negative number of seconds for the activity feed: 45s, 2m 5s, 1h 2m.
export function formatDuration(totalSeconds: number): string {
  if (totalSeconds < 60) {
    return totalSeconds + 's';
  } else {
    if (totalSeconds < 3600) {
      const minutes = Math.floor(totalSeconds / 60);
      const seconds = totalSeconds % 60;
      if (seconds === 0) {
        return minutes + 'm';
      } else {
        return minutes + 'm ' + seconds + 's';
      }
    } else {
      const hours = Math.floor(totalSeconds / 3600);
      const minutes = Math.floor((totalSeconds % 3600) / 60);
      if (minutes === 0) {
        return hours + 'h';
      } else {
        return hours + 'h ' + minutes + 'm';
      }
    }
  }
}
