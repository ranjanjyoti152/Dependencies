import os
import shutil
import yt_dlp
from datetime import datetime, timedelta
import tkinter as tk
from tkinter import ttk, messagebox, scrolledtext


# Function to download YouTube video or audio using yt-dlp
def download_best_format(url, base_path, file_type, output_box):
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
                messagebox.showinfo("Playlist Detected", f"Detected a playlist with {len(info_dict['entries'])} videos.")
                download_choice = messagebox.askyesno("Download Playlist", "Do you want to download the entire playlist?")
                if download_choice:
                    ydl.download([url])
                    output_box.insert(tk.END, f"Downloaded playlist successfully to {save_path}\n")
                    return
                else:
                    # List individual videos for user to choose
                    videos = [entry['title'] for entry in info_dict['entries']]
                    video_list = "\n".join([f"{idx + 1}. {title}" for idx, title in enumerate(videos)])
                    choice = tk.simpledialog.askinteger("Select Video", f"Available videos:\n{video_list}\nEnter video number:")
                    if choice and 0 < choice <= len(info_dict['entries']):
                        video_url = info_dict['entries'][choice - 1]['url']
                        output_box.insert(tk.END, f"Downloading video: {info_dict['entries'][choice - 1]['title']}\n")
                        ydl.download([video_url])
                    else:
                        messagebox.showwarning("Invalid Choice", "No valid video selected.")
                    return

            formats = info_dict.get('formats', [])
            if not formats:
                output_box.insert(tk.END, "No formats available for this video.\n")
                return

            # Filter formats based on the file type
            if file_type == 'Video':
                formats = [f for f in formats if f.get('vcodec') != 'none']  # Only video formats
            elif file_type == 'Audio':
                formats = [f for f in formats if f.get('acodec') != 'none']  # Only audio formats
            else:
                output_box.insert(tk.END, "Invalid file type. Please choose 'Video' or 'Audio'.\n")
                return

            # Display available formats
            format_list = [f"{i + 1}: {f.get('format_note', 'Quality not specified')} {f.get('resolution', 'No resolution')} - {f.get('ext', '')}" for i, f in enumerate(formats)]
            format_list_str = "\n".join(format_list)
            choice = tk.simpledialog.askinteger("Select Format", f"Available formats:\n{format_list_str}\nChoose the format number:")
            if not choice or choice <= 0 or choice > len(formats):
                output_box.insert(tk.END, "Invalid format choice.\n")
                return

            chosen_format = formats[choice - 1]['format_id']

            # Update options for the chosen format
            ydl_opts['format'] = chosen_format

        # Download with yt-dlp
        with yt_dlp.YoutubeDL(ydl_opts) as ydl:
            ydl.download([url])

        output_box.insert(tk.END, f"Downloaded successfully to {save_path}\n")

    except Exception as e:
        output_box.insert(tk.END, f"Error: {e}\n")


# GUI Setup
def setup_gui():
    root = tk.Tk()
    root.title("YouTube Downloader")
    root.geometry("600x400")

    # URL Entry
    ttk.Label(root, text="YouTube URL:").grid(row=0, column=0, padx=10, pady=10, sticky=tk.W)
    url_entry = ttk.Entry(root, width=50)
    url_entry.grid(row=0, column=1, padx=10, pady=10, sticky=tk.W)

    # File Type Selection
    ttk.Label(root, text="File Type:").grid(row=1, column=0, padx=10, pady=10, sticky=tk.W)
    file_type_combo = ttk.Combobox(root, values=["Video", "Audio"], state="readonly")
    file_type_combo.current(0)  # Default to "Video"
    file_type_combo.grid(row=1, column=1, padx=10, pady=10, sticky=tk.W)

    # Output Text Box
    output_box = scrolledtext.ScrolledText(root, width=70, height=15, wrap=tk.WORD)
    output_box.grid(row=3, column=0, columnspan=2, padx=10, pady=10)

    # Base Path for Downloads
    base_path = os.path.join(os.getcwd(), 'downloads')  # Default to 'downloads' in the current working directory

    # Download Button
    def start_download():
        url = url_entry.get().strip()
        file_type = file_type_combo.get()
        if not url:
            messagebox.showwarning("Input Error", "Please enter a valid YouTube URL.")
            return
        output_box.insert(tk.END, f"Starting download for {url} as {file_type}...\n")
        output_box.see(tk.END)  # Scroll to the end of the output box
        download_best_format(url, base_path, file_type, output_box)

    download_button = ttk.Button(root, text="Download", command=start_download)
    download_button.grid(row=2, column=0, columnspan=2, pady=10)

    root.mainloop()


# Run the GUI application
if __name__ == "__main__":
    setup_gui()
