//
//  ViewController.swift
//  ViewRecorder
//
//  Created by David Lee on 12/14/15.
//  Copyright © 2015 David Lee. All rights reserved.
//

import UIKit
import WebKit

class ViewController: UIViewController {

	var recorder: RecordingContextImpl!

	@IBOutlet var webView1: UIWebView!
	@IBOutlet var webView2Placeholder: UIView!
	var webView2: WKWebView!

	override func viewDidLoad() {
		super.viewDidLoad()
		recorder = RecordingContextImpl(view: view)

		webView2 = WKWebView(frame: webView2Placeholder.bounds)
		webView2Placeholder.addSubview(webView2)

		webView1.loadRequest(NSURLRequest(URL: NSURL(string: "https://google.com")!))
		webView2.loadRequest(NSURLRequest(URL: NSURL(string: "https://google.com")!))
	}

	override func didReceiveMemoryWarning() {
		super.didReceiveMemoryWarning()
		// Dispose of any resources that can be recreated.
	}

	@IBAction func takeSnapshot() {
		let snapshot = recorder.snapshot()
		print(snapshot)
	}

	@IBAction func toggleRecording(sender: UISwitch) {
		if sender.on {
			recorder.resumeRecording()
		} else {
			recorder.pauseRecording()
		}
	}

	@IBAction func finishRecording() {
		recorder.exportRecording().onSuccess { (fileURL) -> Void in
			print("exported to ", fileURL)
		}.onFailure { (error) -> Void in
			print("errored", error)
		}
	}
}

