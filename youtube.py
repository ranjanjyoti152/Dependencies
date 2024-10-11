import os
import yt_dlp  # type: ignore
from datetime import datetime
from tqdm import tqdm  # type: ignore
from colorama import Fore, init  # type: ignore
import glob
import platform
import shutil

# Initialize colorama
init(autoreset=True)

# Global variable to keep track of progress
progress_bar = None

# Progress hook function to update the progress bar
def progress_hook(d):
    global progress_bar
    if d['status'] == 'downloading':
        if progress_bar is None:
            total_bytes = d.get('total_bytes') or d.get('total_bytes_estimate')
            progress_bar = tqdm(
                total=total_bytes,
                unit='B',
                unit_scale=True,
                desc=f"{Fore.GREEN}Downloading",
                leave=False,
                miniters=1,
                mininterval=0.5,
                colour='green'
            )
        progress_bar.update(d['downloaded_bytes'] - progress_bar.n)
    elif d['status'] == 'finished':
        if progress_bar is not None:
            progress_bar.close()
        progress_bar = None
        print(f"{Fore.CYAN}\nDownload completed: {d['filename']}")

# Function to delete all .webm files in the directory
def delete_webm_files(directory):
    for webm_file in glob.glob(os.path.join(directory, '*.webm')):
        os.remove(webm_file)
        print(f"{Fore.RED}Deleted: {webm_file}")

# Function to download YouTube video or audio using yt-dlp
def download_best_format(url, base_path=None, file_type='video'):
    # Set default base path based on OS
    if base_path is None:
        if platform.system() == 'Windows':
            base_path = os.path.join(os.path.expanduser('~'), 'Desktop', 'Youtube Downloads')
        else:  # Assuming Linux/Ubuntu or MacOS
            base_path = os.path.join(os.path.expanduser('~'), 'Downloads', 'Youtube Downloads')

    if not os.path.exists(base_path):
        os.makedirs(base_path)

    today = datetime.now().strftime('%Y-%m-%d')
    save_path = os.path.join(base_path, today)
    os.makedirs(save_path, exist_ok=True)

    # yt-dlp options to ensure proper downloading
    ydl_opts = {
        'outtmpl': f'{save_path}/%(title)s.%(ext)s',
        'progress_hooks': [progress_hook],  # Hook for progress updates
        'postprocessors': [{
            'key': 'FFmpegMerger',  # Ensures video and audio streams are merged
        }],
        'noplaylist': False,  # Do not auto-download playlists
        'keepvideo': True,  # Keep the video file after downloading
        'merge_output_format': 'mp4'  # Ensure merging is done in MP4 format
    }

    try:
        with yt_dlp.YoutubeDL(ydl_opts) as ydl:
            info_dict = ydl.extract_info(url, download=False)

            # Handle playlists
            if 'entries' in info_dict:  # Playlist detected
                print(f"{Fore.YELLOW}Detected a playlist with {len(info_dict['entries'])} videos.")
                download_choice = input(f"{Fore.MAGENTA}Do you want to download the entire playlist? (yes/no): ").strip().lower()

                if download_choice == 'yes':
                    ydl.download([url])
                    print(f"{Fore.GREEN}Downloaded playlist successfully to {save_path}")
                    delete_webm_files(save_path)  # Delete .webm files after downloading
                    return
                else:
                    # List individual videos for user to choose
                    for idx, entry in enumerate(info_dict['entries'], 1):
                        print(f"{Fore.YELLOW}{idx}. {entry['title']}")

                    video_index = int(input(f"{Fore.MAGENTA}Enter the number of the video you want to download: ")) - 1
                    video_url = info_dict['entries'][video_index]['url']
                    print(f"{Fore.GREEN}Downloading video: {info_dict['entries'][video_index]['title']}")
                    ydl.download([video_url])
                    delete_webm_files(save_path)  # Delete .webm files after downloading
                    return

            formats = info_dict.get('formats', [])
            if not formats:
                print(f"{Fore.RED}No formats available for this video.")
                return

            # Filter formats based on file type
            if file_type == 'video':
                formats = [f for f in formats if f.get('vcodec') != 'none']  # Ensure video formats are chosen
            elif file_type == 'audio':
                formats = [f for f in formats if f.get('acodec') != 'none']  # Ensure audio formats are chosen
            else:
                print(f"{Fore.RED}Invalid file type. Please choose 'video' or 'audio'.")
                return

            # Display available formats for the user to choose
            print(f"{Fore.CYAN}Available formats (Video + Audio or just Video):")
            for i, f in enumerate(formats):
                quality = f.get('format_note', 'Quality not specified')
                resolution = f.get('resolution', 'No resolution')
                has_audio = ' (Audio included)' if f.get('acodec') != 'none' else ' (Video-only)'
                ext = f.get('ext', '')
                print(f"{Fore.YELLOW}{i + 1}: {quality} {resolution} - {ext}{has_audio}")

            # Input validation for choosing format
            while True:
                choice = input(f"{Fore.MAGENTA}Choose the format by entering the number: ").strip()
                if choice.isdigit() and 1 <= int(choice) <= len(formats):
                    choice = int(choice) - 1
                    break
                else:
                    print(f"{Fore.RED}Invalid input. Please enter a valid number between 1 and {len(formats)}.")

            chosen_format = formats[choice]['format_id']

            # Check if video-only format and download audio separately
            if formats[choice]['acodec'] == 'none':
                print(f"{Fore.YELLOW}Chosen format is video-only. Downloading best available audio stream as well.")
                ydl_opts['format'] = f"{chosen_format}+bestaudio"
            else:
                ydl_opts['format'] = chosen_format

        # Download with yt-dlp
        with yt_dlp.YoutubeDL(ydl_opts) as ydl:
            ydl.download([url])

        print(f"{Fore.GREEN}Downloaded successfully to {save_path}")

    except Exception as e:
        print(f"{Fore.RED}Error: {e}")
    finally:
        # Delete .webm files after processing
        delete_webm_files(save_path)

# Example usage
if __name__ == "__main__":
    while True:
        try:
            video_url = input(f"{Fore.CYAN}Enter the YouTube video or playlist URL: ")
            file_type = input(f"{Fore.CYAN}Enter the file type you want to download (video/audio): ").strip().lower()
            download_best_format(video_url, file_type=file_type)

        except KeyboardInterrupt:
            print(f"\n{Fore.RED}Exiting the program.")
            break
