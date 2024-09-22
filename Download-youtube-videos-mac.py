import os
import yt_dlp
from datetime import datetime

# Function to download YouTube video or audio using yt-dlp
def download_best_format(url, base_path=os.path.expanduser('~/Desktop/Youtube Downloads'), file_type='video'):
    # Create base directory if it doesn't exist
    if not os.path.exists(base_path):
        os.makedirs(base_path)

    # Create a folder for today's date
    today = datetime.now().strftime('%Y-%m-%d')
    save_path = os.path.join(base_path, today)
    os.makedirs(save_path, exist_ok=True)

    # yt-dlp options
    ydl_opts = {
        'outtmpl': f'{save_path}/%(title)s.%(ext)s',  # Save with video title as file name
        'format': 'best',  # Default to the best format
        'noplaylist': False,  # Allow playlist download
    }

    try:
        # Get available formats and check if it's a playlist
        with yt_dlp.YoutubeDL(ydl_opts) as ydl:
            info_dict = ydl.extract_info(url, download=False)
            if 'entries' in info_dict:  # This means it is a playlist
                print(f"Detected a playlist with {len(info_dict['entries'])} videos.")
                download_choice = input("Do you want to download the entire playlist? (yes/no): ").strip().lower()

                if download_choice == 'yes':
                    ydl.download([url])
                    print(f"Downloaded playlist successfully to {save_path}")
                    return
                else:
                    # List individual videos for user to choose
                    for idx, entry in enumerate(info_dict['entries'], 1):
                        print(f"{idx}. {entry['title']}")

                    video_index = int(input("Enter the number of the video you want to download: ")) - 1
                    video_url = info_dict['entries'][video_index]['url']
                    print(f"Downloading video: {info_dict['entries'][video_index]['title']}")
                    ydl.download([video_url])
                    return

            formats = info_dict.get('formats', [])
            if not formats:
                print("No formats available for this video.")
                return

            # Filter formats based on the file type
            if file_type == 'video':
                formats = [f for f in formats if f.get('vcodec') != 'none']  # Only video formats
            elif file_type == 'audio':
                formats = [f for f in formats if f.get('acodec') != 'none']  # Only audio formats
            else:
                print("Invalid file type. Please choose 'video' or 'audio'.")
                return

            # Display available formats
            print("Available formats:")
            for i, f in enumerate(formats):
                quality = f.get('format_note', 'Quality not specified')
                resolution = f.get('resolution', 'No resolution')
                ext = f.get('ext', '')
                print(f"{i + 1}: {quality} {resolution} - {ext}")

            # Ask user to choose format
            choice = int(input("Choose the format by entering the number: ")) - 1
            chosen_format = formats[choice]['format_id']

            # Update options for the chosen format
            ydl_opts['format'] = chosen_format

        # Download with yt-dlp
        with yt_dlp.YoutubeDL(ydl_opts) as ydl:
            ydl.download([url])

        print(f"Downloaded successfully to {save_path}")

    except Exception as e:
        print(f"Error: {e}")

# Example usage
if __name__ == "__main__":
    while True:
        try:
            video_url = input("Enter the YouTube video or playlist URL: ")
            file_type = input("Enter the file type you want to download (video/audio): ").strip().lower()

            # Download based on the selected file type
            download_best_format(video_url, file_type=file_type)

        except KeyboardInterrupt:
            print("\nExiting the program.")
            break  # Exit the loop on Ctrl+C
