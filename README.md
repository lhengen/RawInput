# RawInput
Background USB Scanner Support using the RAWInput API

Thiis application was written using Delphi Tokyo 10.2.  If you get errors opening the DPROJ file, then delete it and Delphi will recreate it from the DPR.  You will then have to manually add the JVCL paths.

The TftRawInputInterceptor class uses the JEDI Jvcl HidController to detect the USB scanner
and fetch it's device information.  The RAW Input API is used to read barcodes, which are then sent to the target window in a Windows message.

On the Right Click local menu for the keyboard list there is a Capture with AutoReconnect option.  If you capture the scanner using that option, you can pull out the USB connector and the app will recognize that the "keyboard" input is no longer available.  If you plug the scanner back in, the app will automatically recognize it, and reconnect.  You can then simply scan the next barcode.

To compile the application define an Environment Variable called JVCL in Delphi to point to the root folder of your JVCL installation.  This environment variable is used in the project search path to locate the JVCL units.  It adds the following paths:

$(jvcl)\run
$(jvcl)\common
