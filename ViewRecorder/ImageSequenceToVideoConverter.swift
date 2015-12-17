//
//  ImageSequenceToVideo.swift
//  ViewRecorder
//
//  Created by David Lee on 12/15/15.
//  Copyright © 2015 David Lee. All rights reserved.
//


// adapted from http://stackoverflow.com/questions/3741323/how-do-i-export-uiimage-array-as-a-movie/3742212#3742212

import Foundation
import AVFoundation
import BrightFutures

private typealias WritingContext = (videoWriter: AVAssetWriter, writerInput: AVAssetWriterInput, adaptor: AVAssetWriterInputPixelBufferAdaptor)

enum ConversionError: ErrorType {
	case ExternalError(ErrorType)
}

func convertImageSequenceToVideo(imageSequence: [UIImage], outputVideoSize: CGSize) -> Future<NSURL, ConversionError> {
	let outputFilePath = (NSTemporaryDirectory() as NSString).stringByAppendingPathComponent("\(NSProcessInfo.processInfo().globallyUniqueString)_vid.mp4")
	let destinationFilePath: NSURL = NSURL(fileURLWithPath: outputFilePath, isDirectory: false)
	return setupWritingContext(outputVideoSize, destinationFilePath: destinationFilePath).flatMap { writingContext -> Future<NSURL, ConversionError> in
		startWritingSession(writingContext)

		var remainingImageSequence: ArraySlice<UIImage> = ArraySlice(imageSequence)
		var isWriting = true
		var frameIndex = 0
		while isWriting {
			let (shouldContinueLoop, framesAdvancedBy) = writeLoop(remainingImageSequence, frameIndex: frameIndex, writingContext: writingContext)

			remainingImageSequence = remainingImageSequence.dropFirst(framesAdvancedBy)
			frameIndex += framesAdvancedBy
			isWriting = shouldContinueLoop
		}

		return finishWritingSession(writingContext)
	}
}


// MARK: - Setup

private func setupWritingContext(size: CGSize, destinationFilePath: NSURL) -> Future<WritingContext, ConversionError> {
	return makeVideoWriterForPath(destinationFilePath, destinationFileType: AVFileTypeQuickTimeMovie).map { videoWriter -> WritingContext in
		let writerInput = makeWriterInputWithSize(size)
		let adaptor = makeWriterInputAdaptorForInput(writerInput)
		videoWriter.addInput(writerInput)
		return (videoWriter, writerInput, adaptor)
	}
}

private func makeVideoWriterForPath(destinationFilePath: NSURL, destinationFileType: String) -> Future<AVAssetWriter, ConversionError> {
	let promise = Promise<AVAssetWriter, ConversionError>()
	var videoWriter: AVAssetWriter!
	do {
		videoWriter = try AVAssetWriter(URL: destinationFilePath, fileType: destinationFileType)
		promise.success(videoWriter)
	} catch let err {
		promise.failure(.ExternalError(err))
	}
	return promise.future
}

private func makeWriterInputWithSize(size: CGSize) -> AVAssetWriterInput {
	return AVAssetWriterInput(mediaType: AVMediaTypeVideo, outputSettings: videoSettingsWithSize(size))
}

private func makeWriterInputAdaptorForInput(writerInput: AVAssetWriterInput) -> AVAssetWriterInputPixelBufferAdaptor {
	return AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: writerInput, sourcePixelBufferAttributes: nil)
}

private func videoSettingsWithSize(size: CGSize) -> [String: AnyObject] {
	return [
		AVVideoCodecKey: AVVideoCodecH264,
		AVVideoWidthKey: size.width,
		AVVideoHeightKey: size.height
	]
}



// MARK: - Writing session

private func startWritingSession(writingContext: WritingContext) {
	writingContext.videoWriter.startWriting()
	writingContext.videoWriter.startSessionAtSourceTime(kCMTimeZero)
}

private func writeLoop(frames: ArraySlice<UIImage>, frameIndex: Int, writingContext: WritingContext) -> (continueLoop: Bool, framesAdvancedBy: Int) {
	guard writingContext.writerInput.readyForMoreMediaData else { return (true, 0) }

	/*
	CMTime = Value and Timescale.
	Timescale = the number of tics per second you want
	Value = the number of tics

	Each frame we add will be 1/4th of a second.
	Apple recommend 600 tics per second for video because it is a multiple of the standard video rates 24, 30, 60 fps etc.
	*/
	let frameDurationInSeconds: Float = 0.01666
	let ticsPerSecond: Float = 600
	let frameDuration: CMTime = CMTimeMake(Int64(frameDurationInSeconds * ticsPerSecond), Int32(ticsPerSecond))
	let previousTime: CMTime = CMTimeMake(Int64(frameIndex) * frameDuration.value, Int32(ticsPerSecond))
	// This switch ensures the first frame starts at 0.
	let currentTime: CMTime = frameIndex == 0 ? CMTimeMake(0, Int32(ticsPerSecond)) : CMTimeAdd(previousTime, frameDuration)

	if frameIndex <= frames.count, let buffer = pixelBufferFromImage(frames[frameIndex]) {
		// Append frame to writer.
		writingContext.adaptor.appendPixelBuffer(buffer, withPresentationTime: currentTime)
		return (true, 1)
	} else {
		return (false, 0)
	}
}

private func finishWritingSession(writingContext: WritingContext) -> Future<NSURL, ConversionError> {
	let promise = Promise<NSURL, ConversionError>()

	writingContext.writerInput.markAsFinished()
	writingContext.videoWriter.finishWritingWithCompletionHandler {
		if writingContext.videoWriter.status == .Completed {
			promise.success(writingContext.videoWriter.outputURL)
		} else {
			promise.failure(.ExternalError(writingContext.videoWriter.error!))
		}
	}
	// TODO: `CVPixelBufferPoolRelease` is no longer available. Does this work as a replacement?
//	CVPixelBufferPoolFlush(writingContext.adaptor.pixelBufferPool!, kCVPixelBufferPoolFlushExcessBuffers)

	return promise.future
}


private func pixelBufferFromImage(image: UIImage) -> CVPixelBuffer? {
	return pixelBufferFromImage(image.CGImage)
}

private func pixelBufferFromImage(image: CGImage?) -> CVPixelBuffer? {
	let imageWidth = CGImageGetWidth(image)
	let imageHeight = CGImageGetHeight(image)
	let dictKeys = [kCVPixelBufferCGImageCompatibilityKey, kCVPixelBufferCGBitmapContextCompatibilityKey]
	let dictValues = [true, true]
	let pixelBufferAttributes: CFDictionary = CFDictionaryCreate(kCFAllocatorDefault, UnsafeMutablePointer(dictKeys), UnsafeMutablePointer(dictValues), dictKeys.count, nil, nil)

	// Create the pixel buffer.

	var pixelBufferOrNil: CVPixelBufferRef?
	let status = CVPixelBufferCreate(kCFAllocatorDefault, imageWidth, imageHeight, kCVPixelFormatType_32ARGB, pixelBufferAttributes, &pixelBufferOrNil)

	guard status == kCVReturnSuccess else { return nil }
	guard let pixelBuffer = pixelBufferOrNil else { return nil }

	CVPixelBufferLockBaseAddress(pixelBuffer, 0)
	let pixelDataPointer = CVPixelBufferGetBaseAddress(pixelBuffer)
	guard pixelDataPointer != nil else { return nil }


	// Create output bitmap context.

	let bitsPerComponent = 8
	let bytesPerRow = 4 * imageWidth
	var colorSpace = CGColorSpaceCreateDeviceRGB()
	let bitmapInfo = CGImageAlphaInfo.NoneSkipFirst

	var bitmapContext: CGContextRef? = CGBitmapContextCreate(pixelDataPointer, imageWidth, imageHeight, bitsPerComponent, bytesPerRow, colorSpace, bitmapInfo.rawValue)


	// Write from input context to output context.

	CGContextConcatCTM(bitmapContext, CGAffineTransformMakeRotation(0)) // ??
	CGContextDrawImage(bitmapContext, CGRect(x: 0, y: 0, width: imageWidth, height: imageHeight), image)
//	CGColorSpaceRelease(colorSpace)
//	CGContextRelease(bitmapContext)
	colorSpace = nil
	bitmapContext = nil
	CVPixelBufferUnlockBaseAddress(pixelBuffer, 0)
	return pixelBuffer
}